# zHex

This small program takes in a filepath and prints the contained binary data in hexadecimal format.


Output is similar to Powershell's [Format-Hex](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/format-hex?view=powershell-7.4) Cmdlet, but is by default formatted with colour and separators. To the right of the hex data, a column is printed containing ASCII representations of bytes where possible.

By default 16 bytes are printed per line, with a vertical pipe visually separating the first and second 8 bytes. Bytes per line and position of the separator can be changed with -l/-line_length and -i/-intermed_line args.

ASCII control characters are displayed as the unicode control symbols. This behaviour can be turned off using the -u flag.

Colours can be turned off with the -g flag.

Both the above options should be turned off if directing the output into a text file, as they insert escape characters to format text displayed in the terminal.

## Building

Requires Zig Version 0.13.0.


Simply clone the repository to your machine and run `zig build`.


## Usage

    -s, --start <usize>...
            Byte offset to start at. (default: 0)

    -e, --end <usize>...
            Byte offset to end at. (default: end of file)

    -n, --nlines <usize>
            Number of lines to print. (default: no limit) Note: The program will stop after n
            lines are printed, or when the end byte offset is reached. Whichever comes first.

    -l, --line_length <usize>
            Number of bytes to print per line. (default: 16)

    -i, --intermed_line <usize>
            Number of bytes to print between spacer lines. (default: 8)

    -d, --decimal_address
            Print start-of-line address in decimal instead of hex.

    -g, --disable_color
            Disable color output (useful for piping output to readable file).

    -t, --utf8
            Use UTF-8 encoding for output (Won't display control characters as unicode control
            symbols). Useful for piping output to readable file.

    <str>...
            File to read.

## Attribution

The program uses [Hejsil](https://github.com/Hejsil/)'s [Zig-CLAP](https://github.com/Hejsil/zig-clap) library, licensed using the MIT License.
