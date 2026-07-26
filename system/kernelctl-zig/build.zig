const root = @import("../alpenglow-ctl/build.zig");

pub fn build(b: *@import("std").Build) void {
    root.build(b);
}
