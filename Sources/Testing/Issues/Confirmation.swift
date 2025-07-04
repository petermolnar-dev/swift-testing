//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

private import _TestingInternals

/// A type that can be used to confirm that an event occurs zero or more times.
public struct Confirmation: Sendable {
  /// The number of times ``confirm(count:)`` has been called.
  ///
  /// This property is fileprivate because it may be mutated asynchronously and
  /// callers may be tempted to use it in ways that result in data races.
  fileprivate var count = Locked(rawValue: 0)

  /// Confirm this confirmation.
  ///
  /// - Parameters:
  ///   - count: The number of times to confirm this instance.
  ///
  /// As a convenience, this method can be called by calling the confirmation
  /// directly.
  public func confirm(count: Int = 1) {
    precondition(count > 0)
    self.count.add(count)
  }
}

// MARK: -

extension Confirmation {
  /// Confirm this confirmation.
  ///
  /// - Parameters:
  ///   - count: The number of times to confirm this instance.
  ///
  /// Calling a confirmation as a function is shorthand for calling its
  /// ``confirm(count:)`` method.
  public func callAsFunction(count: Int = 1) {
    confirm(count: count)
  }
}

// MARK: -

/// Confirm that some event occurs during the invocation of a function.
///
/// - Parameters:
///   - comment: An optional comment to apply to any issues generated by this
///     function.
///   - expectedCount: The number of times the expected event should occur when
///     `body` is invoked. The default value of this argument is `1`, indicating
///     that the event should occur exactly once. Pass `0` if the event should
///     _never_ occur when `body` is invoked.
///   - isolation: The actor to which `body` is isolated, if any.
///   - sourceLocation: The source location to which any recorded issues should
///     be attributed.
///   - body: The function to invoke.
///
/// - Returns: Whatever is returned by `body`.
///
/// - Throws: Whatever is thrown by `body`.
///
/// Use confirmations to check that an event occurs while a test is running in
/// complex scenarios where `#expect()` and `#require()` are insufficient. For
/// example, a confirmation may be useful when an expected event occurs:
///
/// - In a context that cannot be awaited by the calling function such as an
///   event handler or delegate callback;
/// - More than once, or never; or
/// - As a callback that is invoked as part of a larger operation.
///
/// To use a confirmation, pass a closure containing the work to be performed.
/// The testing library will then pass an instance of ``Confirmation`` to the
/// closure. Every time the event in question occurs, the closure should call
/// the confirmation:
///
/// ```swift
/// let n = 10
/// await confirmation("Baked buns", expectedCount: n) { bunBaked in
///   foodTruck.eventHandler = { event in
///     if event == .baked(.cinnamonBun) {
///       bunBaked()
///     }
///   }
///   await foodTruck.bake(.cinnamonBun, count: n)
/// }
/// ```
///
/// When the closure returns, the testing library checks if the confirmation's
/// preconditions have been met, and records an issue if they have not.
public func confirmation<R>(
  _ comment: Comment? = nil,
  expectedCount: Int = 1,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Confirmation) async throws -> sending R
) async rethrows -> R {
  try await confirmation(
    comment,
    expectedCount: expectedCount ... expectedCount,
    isolation: isolation,
    sourceLocation: sourceLocation,
    body
  )
}

// MARK: - Ranges as expected counts

/// Confirm that some event occurs during the invocation of a function.
///
/// - Parameters:
///   - comment: An optional comment to apply to any issues generated by this
///     function.
///   - expectedCount: A range of integers indicating the number of times the
///     expected event should occur when `body` is invoked.
///   - isolation: The actor to which `body` is isolated, if any.
///   - sourceLocation: The source location to which any recorded issues should
///     be attributed.
///   - body: The function to invoke.
///
/// - Returns: Whatever is returned by `body`.
///
/// - Throws: Whatever is thrown by `body`.
///
/// Use confirmations to check that an event occurs while a test is running in
/// complex scenarios where `#expect()` and `#require()` are insufficient. For
/// example, a confirmation may be useful when an expected event occurs:
///
/// - In a context that cannot be awaited by the calling function such as an
///   event handler or delegate callback;
/// - More than once, or never; or
/// - As a callback that is invoked as part of a larger operation.
///
/// To use a confirmation, pass a closure containing the work to be performed.
/// The testing library will then pass an instance of ``Confirmation`` to the
/// closure. Every time the event in question occurs, the closure should call
/// the confirmation:
///
/// ```swift
/// let minBuns = 5
/// let maxBuns = 10
/// await confirmation(
///   "Baked between \(minBuns) and \(maxBuns) buns",
///   expectedCount: minBuns ... maxBuns
/// ) { bunBaked in
///   foodTruck.eventHandler = { event in
///     if event == .baked(.cinnamonBun) {
///       bunBaked()
///     }
///   }
///   await foodTruck.bakeTray(of: .cinnamonBun)
/// }
/// ```
///
/// When the closure returns, the testing library checks if the confirmation's
/// preconditions have been met, and records an issue if they have not.
///
/// If an exact count is expected, use
/// ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-5mqz2`` instead.
///
/// @Metadata {
///   @Available(Swift, introduced: 6.1)
///   @Available(Xcode, introduced: 16.3)
/// }
public func confirmation<R>(
  _ comment: Comment? = nil,
  expectedCount: some RangeExpression<Int> & Sequence<Int> & Sendable,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Confirmation) async throws -> sending R
) async rethrows -> R {
  let confirmation = Confirmation()
  defer {
    let actualCount = confirmation.count.rawValue
    if !expectedCount.contains(actualCount) {
      let issue = Issue(
        kind: .confirmationMiscounted(actual: actualCount, expected: expectedCount),
        comments: Array(comment),
        sourceContext: .init(backtrace: .current(), sourceLocation: sourceLocation)
      )
      issue.record()
    }
  }
  return try await body(confirmation)
}

/// An overload of ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-l3il``
/// that handles the unbounded range operator (`...`).
///
/// This overload is necessary because `UnboundedRange` does not conform to
/// `RangeExpression`. It effectively always succeeds because any number of
/// confirmations matches, so it is marked unavailable and is not implemented.
@available(*, unavailable, message: "Unbounded range '...' has no effect when used with a confirmation.")
public func confirmation<R>(
  _ comment: Comment? = nil,
  expectedCount: UnboundedRange,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Confirmation) async throws -> R
) async rethrows -> R {
  swt_unreachable()
}

/// An overload of ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-l3il``
/// that handles the partial-range-through operator (`...n`).
///
/// This overload is necessary because the lower bound of `PartialRangeThrough`
/// is ambiguous: does it start at `0` or `1`? Test authors should specify a
@available(*, unavailable, message: "Range expression '...n' is ambiguous without an explicit lower bound")
public func confirmation<R>(
  _ comment: Comment? = nil,
  expectedCount: PartialRangeThrough<Int>,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Confirmation) async throws -> R
) async rethrows -> R {
  swt_unreachable()
}

/// An overload of ``confirmation(_:expectedCount:isolation:sourceLocation:_:)-l3il``
/// that handles the partial-range-up-to operator (`..<n`).
///
/// This overload is necessary because the lower bound of `PartialRangeUpTo` is
/// ambiguous: does it start at `0` or `1`? Test authors should specify a
@available(*, unavailable, message: "Range expression '..<n' is ambiguous without an explicit lower bound")
public func confirmation<R>(
  _ comment: Comment? = nil,
  expectedCount: PartialRangeUpTo<Int>,
  isolation: isolated (any Actor)? = #isolation,
  sourceLocation: SourceLocation = #_sourceLocation,
  _ body: (Confirmation) async throws -> R
) async rethrows -> R {
  swt_unreachable()
}
