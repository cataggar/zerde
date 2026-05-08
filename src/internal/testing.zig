//! Internal shared testing helpers.

const std = @import("std");

/// Shared testing allocator for Zerde tests.
pub const allocator = std.testing.allocator;
