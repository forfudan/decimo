"""Test the I/O utilities: line splitting, comment handling, text processing."""

from std import testing

from calculator.io import (
    _to_cstr,
    file_exists,
    filter_expression_lines,
    is_blank,
    is_comment_or_blank,
    read_file_text,
    split_into_lines,
    strip,
    strip_comment,
)


# ===----------------------------------------------------------------------=== #
# split_into_lines
# ===----------------------------------------------------------------------=== #


def test_split_empty() raises:
    var lines = split_into_lines(String(""))
    testing.assert_equal(len(lines), 0)


def test_split_single_line() raises:
    var lines = split_into_lines(String("hello"))
    testing.assert_equal(len(lines), 1)
    testing.assert_equal(lines[0], "hello")


def test_split_multiple_lines() raises:
    var lines = split_into_lines(String("a\nb\nc"))
    testing.assert_equal(len(lines), 3)
    testing.assert_equal(lines[0], "a")
    testing.assert_equal(lines[1], "b")
    testing.assert_equal(lines[2], "c")


def test_split_trailing_newline() raises:
    var lines = split_into_lines(String("a\nb\n"))
    testing.assert_equal(len(lines), 2)
    testing.assert_equal(lines[0], "a")
    testing.assert_equal(lines[1], "b")


def test_split_blank_lines() raises:
    var lines = split_into_lines(String("a\n\nb\n\n"))
    testing.assert_equal(len(lines), 4)
    testing.assert_equal(lines[0], "a")
    testing.assert_equal(lines[1], "")
    testing.assert_equal(lines[2], "b")
    testing.assert_equal(lines[3], "")


def test_split_crlf() raises:
    var lines = split_into_lines(String("a\r\nb\r\n"))
    testing.assert_equal(len(lines), 2)
    testing.assert_equal(lines[0], "a")
    testing.assert_equal(lines[1], "b")


# ===----------------------------------------------------------------------=== #
# strip_comment
# ===----------------------------------------------------------------------=== #


def test_strip_comment_empty() raises:
    testing.assert_equal(strip_comment(String("")), "")


def test_strip_comment_no_hash() raises:
    testing.assert_equal(strip_comment(String("1+2")), "1+2")
    testing.assert_equal(strip_comment(String("sqrt(2)")), "sqrt(2)")


def test_strip_comment_full_line_comment() raises:
    testing.assert_equal(strip_comment(String("# comment")), "")
    testing.assert_equal(strip_comment(String("#")), "")


def test_strip_comment_inline_comment() raises:
    testing.assert_equal(strip_comment(String("1+2 # add")), "1+2 ")
    testing.assert_equal(strip_comment(String("pi # constant")), "pi ")
    testing.assert_equal(strip_comment(String("sqrt(2)#no space")), "sqrt(2)")


def test_strip_comment_indented_comment() raises:
    testing.assert_equal(strip_comment(String("  # indented")), "  ")


# ===----------------------------------------------------------------------=== #
# is_blank
# ===----------------------------------------------------------------------=== #


def test_is_blank_empty() raises:
    testing.assert_true(is_blank(String("")))


def test_is_blank_whitespace() raises:
    testing.assert_true(is_blank(String("   ")))
    testing.assert_true(is_blank(String("\t\t")))
    testing.assert_true(is_blank(String("  \t ")))


def test_is_blank_not_blank() raises:
    testing.assert_false(is_blank(String("1+2")))
    testing.assert_false(is_blank(String("  x")))
    testing.assert_false(is_blank(String("#")))


# ===----------------------------------------------------------------------=== #
# strip
# ===----------------------------------------------------------------------=== #


def test_strip_basic() raises:
    testing.assert_equal(strip(String("  hello  ")), "hello")
    testing.assert_equal(strip(String("\thello\t")), "hello")
    testing.assert_equal(strip(String("  hello")), "hello")
    testing.assert_equal(strip(String("hello  ")), "hello")


def test_strip_empty() raises:
    testing.assert_equal(strip(String("")), "")
    testing.assert_equal(strip(String("   ")), "")


def test_strip_no_change() raises:
    testing.assert_equal(strip(String("hello")), "hello")


# ===----------------------------------------------------------------------=== #
# is_comment_or_blank
# ===----------------------------------------------------------------------=== #


def test_blank_line() raises:
    testing.assert_true(is_comment_or_blank(String("")))


def test_whitespace_only() raises:
    testing.assert_true(is_comment_or_blank(String("   ")))
    testing.assert_true(is_comment_or_blank(String("\t\t")))
    testing.assert_true(is_comment_or_blank(String("  \t ")))


def test_comment_line() raises:
    testing.assert_true(is_comment_or_blank(String("# comment")))
    testing.assert_true(is_comment_or_blank(String("  # indented comment")))
    testing.assert_true(is_comment_or_blank(String("\t# tab comment")))


def test_expression_line() raises:
    testing.assert_false(is_comment_or_blank(String("1+2")))
    testing.assert_false(is_comment_or_blank(String("  sqrt(2)")))
    testing.assert_false(is_comment_or_blank(String("pi")))


# ===----------------------------------------------------------------------=== #
# filter_expression_lines
# ===----------------------------------------------------------------------=== #


def test_filter_basic() raises:
    var lines = List[String]()
    lines.append(String("# comment"))
    lines.append(String(""))
    lines.append(String("1+2"))
    lines.append(String("  sqrt(2)  "))
    lines.append(String(""))
    lines.append(String("# another comment"))
    lines.append(String("pi"))
    var filtered = filter_expression_lines(lines)
    testing.assert_equal(len(filtered), 3)
    testing.assert_equal(filtered[0], "1+2")
    testing.assert_equal(filtered[1], "sqrt(2)")
    testing.assert_equal(filtered[2], "pi")


# ===----------------------------------------------------------------------=== #
# file_exists
# ===----------------------------------------------------------------------=== #


def test_file_exists_nonexistent() raises:
    # Use a path with enough entropy to avoid false positives on any machine.
    testing.assert_false(
        file_exists(String("/tmp/_decimo_no_such_file_a1b2c3d4e5f6_.dm"))
    )


# ===----------------------------------------------------------------------=== #
# read_file_text
# ===----------------------------------------------------------------------=== #


def test_read_file_text_round_trip() raises:
    """What is written comes back, newlines and all.

    The file is written here rather than taken from `tests/cli/test_data`, so
    the test does not depend on the directory it is run from.

    This function used to redirect stdin at the file with `dup2` and read it
    through `getchar`, restoring stdin afterwards. It had no test. It now
    uses the standard library's file handle, and the last assertion is the
    one the old implementation had to work for: reading a file must leave
    stdin alone.
    """
    var path = String("/tmp/_decimo_read_file_text_b7f3c1a9.dm")
    var contents = String("pi\n# a comment\n\nsqrt(2)\n")

    with open(path, "w") as handle:
        handle.write(contents)

    testing.assert_true(file_exists(path))
    testing.assert_equal(read_file_text(path), contents)

    # Twice in a row: nothing is consumed by the first read.
    testing.assert_equal(read_file_text(path), contents)

    # An empty file is an empty string, not a failure.
    var empty = String("/tmp/_decimo_read_file_text_empty_b7f3c1a9.dm")
    with open(empty, "w") as handle:
        handle.write(String(""))
    testing.assert_equal(read_file_text(empty), String(""))


def test_read_file_text_refuses_a_missing_file() raises:
    var raised = False
    try:
        _ = read_file_text(String("/tmp/_decimo_no_such_file_a1b2c3d4e5f6_.dm"))
    except:
        raised = True
    testing.assert_true(raised, "a missing file has to raise")


# ===----------------------------------------------------------------------=== #
# _to_cstr
# ===----------------------------------------------------------------------=== #


def test_to_cstr() raises:
    var result = _to_cstr(String("hello"))
    testing.assert_equal(len(result), 6)  # 5 chars + null terminator
    testing.assert_equal(result[5], UInt8(0))


# ===----------------------------------------------------------------------=== #
# main
# ===----------------------------------------------------------------------=== #


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
