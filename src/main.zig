//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");
const clap = @import("clap");
const builtin = @import("builtin");

const debug = std.debug;
const io = std.io;
var COLOR = true;
var UTF16 = true;
var SEPARATOR_COLOR = io.tty.Color.bright_green;
var SEPARATOR = "|";
var ADDRESS_COLOR = io.tty.Color.yellow;
var PRINTABLE_COLOR = io.tty.Color.reset;
var NON_PRINTABLE_COLOR = io.tty.Color.red;
var NON_ASCII_COLOR = io.tty.Color.cyan;
var NULL_COLOR = io.tty.Color.dim;

///Changes the codepage on windows to one that works with utf-8 characters, then changes it back to the original codepage on deinit
const UTF8ConsoleOutput = struct {
    ///The original codepage number
    original: c_uint = undefined,

    ///Changes the codepage to 65001 (utf-8) on windows and saves the original codepage number
    fn init() UTF8ConsoleOutput {
        var self = UTF8ConsoleOutput{};
        if (builtin.target.os.tag == .windows) {
            const kernel32 = std.os.windows.kernel32;
            self.original = kernel32.GetConsoleOutputCP();
            _ = kernel32.SetConsoleOutputCP(65001);
        }
        return self;
    }

    ///Changes the codepage back to the original codepage number (init must have been called first)
    fn deinit(self: *UTF8ConsoleOutput) void {
        if (self.original != undefined) {
            _ = std.os.windows.kernel32.SetConsoleOutputCP(self.original);
        }
    }
};

///Define the print function to print to stdout (because i am lazy)
fn print(comptime fmt: []const u8, args: anytype) void {
    io.getStdOut().writer().print(fmt, args) catch {};
}

///Change the color of any text in the terminal after this function is called
fn setColor(color: std.io.tty.Color) void {
    const config = io.tty.detectConfig(std.io.getStdOut());
    config.setColor(io.getStdOut(), color) catch unreachable;
}

///Reset the color to default for any text in the terminal after this function is called
fn resetColor() void {
    const config = io.tty.detectConfig(io.getStdOut());
    config.setColor(io.getStdOut(), io.tty.Color.reset) catch unreachable;
}

fn printColor(color: std.io.tty.Color, comptime fmt: []const u8, args: anytype) void {
    if (!COLOR) {
        print(fmt, args);
        return;
    }
    setColor(color);
    defer resetColor();
    print(fmt, args);
}

///Prints a line of text, displaying non-printable characters as red utf-8 control symbols, and showing non-ascii characters as a cyan dot
fn printLine(line: []u8, len: usize) void {
    for (0.., line) |i, character| {
        if (i >= len) {
            break;
        }
        var c = character;
        //Print control characters as red unicode control symbols
        if (c < 32) {
            if (UTF16) {
                var char: u16 = @as(u16, c);
                char = char + 0x2400; //unicode control symbols start at 0x2400
                printColor(NON_PRINTABLE_COLOR, "{u}", .{char});
            } else {
                if (c == 10) {
                    c = 191; // newline

                } else if (c == 13) {
                    c = 187; // carriage return
                } else if (c == 9) {
                    c = 194; // tab
                } else if (c == 0) {
                    c = 219; // null
                } else {
                    c = 250; // middle dot
                }
                printColor(NON_PRINTABLE_COLOR, "{c}", .{c});
            }
        } else if (c < 255) { //print printable ascii characters as is
            printColor(PRINTABLE_COLOR, "{c}", .{c});
        } else { //print non-ascii characters as cyan dots
            printColor(NON_ASCII_COLOR, ".", .{});
        }
    }
}

const context_t = struct {
    nlines: usize,
    start: usize,
    end: usize,
    line_length: usize,
    intermediate_tab: usize,
    decimal_address: bool,
    row: usize,
    col: usize,
    complete: bool,
    line: []u8,
    allocator: std.mem.Allocator,
};

fn processData(file_contents: []u8, context: *context_t) void {
    const start_address = context.start;
    for (start_address.., file_contents) |addr, c| {
        if (context.complete or addr >= context.end) {
            break;
        }
        defer {
            context.col += 1;
            context.start = addr + 1;
            if (context.col == context.line_length) { //reset the column counter at the end of the line and print the line
                context.col = 0;
                context.row += 1;

                printColor(SEPARATOR_COLOR, "  |", .{});
                printLine(context.line, context.line_length);
                printColor(SEPARATOR_COLOR, "|\n", .{});

                if (context.nlines != 0 and context.row >= context.nlines) {
                    context.complete = true;
                }

                //reset the line buffer
                context.allocator.free(context.line);
                context.line = context.allocator.alloc(
                    u8,
                    context.line_length,
                ) catch unreachable;
            }
        }

        //print the address at the start of the line
        if (context.col == 0) {
            if (context.decimal_address) {
                printColor(ADDRESS_COLOR, "{d:0>6}:", .{addr});
            } else {
                printColor(ADDRESS_COLOR, "0x{x:0>4}:", .{addr});
            }
        }

        //print the space between bytes
        print(" ", .{});

        //print a wider space
        if (context.col > 0 and context.col % context.intermediate_tab == 0) {
            printColor(SEPARATOR_COLOR, "| ", .{});
        }

        context.line[context.col] = c;
        var color = PRINTABLE_COLOR;
        if (c == 0) {
            color = NULL_COLOR;
        }
        printColor(color, "{x:0>2}", .{c});
    }
}

pub fn main() !void {
    defer resetColor();

    //Initialize the general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var context = context_t{
        .nlines = 0,
        .start = 0,
        .end = std.math.maxInt(usize),
        .line_length = 16,
        .intermediate_tab = 8,
        .decimal_address = false,
        .row = 0,
        .col = 0,
        .complete = false,
        .line = undefined,
        .allocator = allocator,
    };

    //defining the parameters for the clap Command Line Args parser
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                    Display this help and exit.
        \\-u, --usage                   Display a short usage message and exit.
        \\-s, --start <usize>...        Byte offset to start at. (default: 0)
        \\-e, --end <usize>...          Byte offset to end at. (default: end of file)
        \\-n, --nlines <usize>          Number of lines to print. (default: no limit)
        \\                              Note: The program will stop after n lines are printed, or when the end byte offset is reached. Whichever comes first.
        \\-l, --line_length <usize>     Number of bytes to print per line. (default: 16)
        \\-i, --intermed_line <usize>   Number of bytes to print between spacer lines. (default: 8)
        \\-d, --decimal_address         Print start-of-line address in decimal instead of hex.
        \\-g, --disable_color           Disable color output (useful for piping output to readable file).
        \\-t, --utf8                    Use UTF-8 encoding for output (Won't display control characters as unicode control symbols).
        \\                              Useful for piping output to readable file.
        \\<str>...                      File to read.
        \\
    );

    // Initialize clap diagnostic and parse the arguments
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        //io.getStdErr().writer().print("Error: invalid arguments\n", .{}) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    if (res.args.usage != 0)
        return clap.usage(io.getStdErr().writer(), clap.Help, &params);
    if (res.args.nlines) |n| {
        context.nlines = n;
        //print("--nlines = {}\n", .{n});
    }
    if (res.args.line_length) |l| {
        context.line_length = l;
        //print("--line_length = {}\n", .{l});
    }
    if (res.args.intermed_line) |i| {
        context.intermediate_tab = i;
        if (context.intermediate_tab == 0) {
            context.intermediate_tab = context.line_length;
        }
        //print("--intermediate_tab = {}\n", .{i});
    }
    if (res.args.decimal_address != 0) {
        context.decimal_address = true;
        //print("--decimal_address\n", .{});
    }
    if (res.args.disable_color != 0) {
        COLOR = false;
        //print("--disable_color\n", .{});
    }
    if (res.args.utf8 != 0) {
        UTF16 = false;
        //print("--utf8\n", .{});
    }
    for (res.args.start) |s| {
        context.start = s;
        //print("--start = {}\n", .{s});
    }
    for (res.args.end) |e| {
        if (e > context.start) {
            context.end = e;
        } else {
            print("Error: end offset must be greater than start offset if defined\n", .{});
            return;
        }
        //print("--end = {}\n", .{e});
    }

    //Change codepage to print unicode characters if the OS is Windows
    var cp_output = UTF8ConsoleOutput.init();
    if (!UTF16) {
        cp_output.deinit();
    }

    defer cp_output.deinit();

    var file = try std.fs.cwd().openFile(res.positionals[0], .{ .mode = .read_only });
    defer file.close();

    context.line = try allocator.alloc(
        u8,
        context.line_length,
    );
    defer context.allocator.free(context.line);

    //const reader = file.reader();

    //const mb = (1 << 10) << 10;
    var buffer_si: usize = context.line_length * context.nlines;
    if (buffer_si == 0) {
        buffer_si = (1 << 10) << 10;
    }

    buffer_si = 127;

    const data_buffer = try allocator.alloc(u8, buffer_si);
    defer allocator.free(data_buffer);
    var br = io.bufferedReader(file.reader());
    var reader = br.reader();

    _ = reader.skipBytes(context.start, .{}) catch {
        print("Error: start offset is beyond the end of the file\n", .{});
        return;
    };

    while (!context.complete) {
        const bytes_read = br.read(data_buffer) catch unreachable;
        if (bytes_read == 0) {
            break;
        }

        processData(data_buffer[0..bytes_read], &context);
    }

    //print the last line if it is not complete
    if (context.col != 0) {
        var i = context.col;

        //pad the line to match previous rows
        while (i < context.line_length) {
            defer {
                i += 1;
            }
            if (i % context.intermediate_tab == 0 and i < context.line_length) {
                printColor(SEPARATOR_COLOR, " |", .{});
            }
            print("   ", .{});
        }

        printColor(SEPARATOR_COLOR, "  |", .{});
        printLine(context.line, context.col);
        printColor(SEPARATOR_COLOR, "|\n", .{});
    }
}
