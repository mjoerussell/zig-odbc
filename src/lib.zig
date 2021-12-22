//! This ODBC interface provides low-level bindings to ODBC drivers.
//! This package does not natively provide support for high-level features such as:
//! * Async event handling
//! * Automated result set binding/iteration
//! * Automatic parameter binding
//!
//! These features should be provided by another library if desired - the point of this library
//! is just to provide an idiomatic Zig interface to direct ODBC functions with better typechecking.

pub const Types = @import("types.zig");
pub const Error = @import("error.zig");
pub const Environment = @import("environment.zig").Environment;
pub const Connection = @import("connection.zig").Connection;
pub const Statement = @import("statement.zig").Statement;
pub const sys = @import("c.zig");
