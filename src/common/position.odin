package common

import "core:strings"
import "core:unicode/utf8"
import "core:fmt"
import "core:odin/ast"

/*
	This file handles the conversion between utf-16 and utf-8 offsets in the text document
*/

//TODO(Optimize by calculating all the newlines at parse instead of calculating them)

Position :: struct {
	line:      int,
	character: int,
}

Range :: struct {
	start: Position,
	end:   Position,
}

Location :: struct {
	uri:   string,
	range: Range,
}

AbsoluteRange :: struct {
	start: int,
	end:   int,
}

AbsolutePosition :: int;

get_absolute_position :: proc (position: Position, document_text: []u8) -> (AbsolutePosition, bool) {
	absolute: AbsolutePosition;

	if len(document_text) == 0 {
		absolute = 0;
		return absolute, true;
	}

	line_count := 0;
	index      := 1;
	last       := document_text[0];

	if !get_index_at_line(&index, &line_count, &last, document_text, position.line) {
		return absolute, false;
	}

	absolute = index + get_character_offset_u16_to_u8(position.character, document_text[index:]);

	return absolute, true;
}

get_relative_token_position :: proc (offset: int, document_text: []u8, current_start: int) -> Position {

	start_index := current_start;

	data := document_text[start_index:];

	i: int;

	position: Position;

	for i + start_index < offset {

		r, w := utf8.decode_rune(data[i:]);

		if r == '\n' { //\r?
			position.character = 0;
			position.line += 1;
			i             += 1;
		} else if w == 0 {
			return position;
		} else {
			if r < 0x10000 {
				position.character += 1;
			} else {
				position.character += 2;
			}

			i += w;
		}
	}

	return position;
}

/*
	Get the range of a token in utf16 space
*/
get_token_range :: proc (node: ast.Node, document_text: []u8) -> Range {
	range: Range;

	go_backwards_to_endline :: proc (offset: int, document_text: []u8) -> int {

		index := offset;

		for index > 0 && document_text[index] != '\n' && document_text[index] != '\r' {
			index -= 1;
		}

		if index == 0 {
			return 0;
		}

		return index + 1;
	};

	pos_offset := min(len(document_text) - 1, node.pos.offset);
	end_offset := min(len(document_text) - 1, node.end.offset);

	offset := go_backwards_to_endline(pos_offset, document_text);

	range.start.line      = node.pos.line - 1;
	range.start.character = get_character_offset_u8_to_u16(node.pos.column - 1, document_text[offset:]);

	offset = go_backwards_to_endline(end_offset, document_text);

	range.end.line      = node.end.line - 1;
	range.end.character = get_character_offset_u8_to_u16(node.end.column - 1, document_text[offset:]);

	return range;
}

get_absolute_range :: proc (range: Range, document_text: []u8) -> (AbsoluteRange, bool) {

	absolute: AbsoluteRange;

	if len(document_text) == 0 {
		absolute.start = 0;
		absolute.end   = 0;
		return absolute, true;
	}

	line_count := 0;
	index      := 1;
	last       := document_text[0];

	if !get_index_at_line(&index, &line_count, &last, document_text, range.start.line) {
		return absolute, false;
	}

	absolute.start = index + get_character_offset_u16_to_u8(range.start.character, document_text[index:]);

	//if the last line was indexed at zero we have to move it back to index 1.
	//This happens when line = 0
	if index == 0 {
		index = 1;
	}

	if !get_index_at_line(&index, &line_count, &last, document_text, range.end.line) {
		return absolute, false;
	}

	absolute.end = index + get_character_offset_u16_to_u8(range.end.character, document_text[index:]);

	return absolute, true;
}

get_index_at_line :: proc (current_index: ^int, current_line: ^int, last: ^u8, document_text: []u8, end_line: int) -> bool {

	if end_line == 0 {
		current_index^ = 0;
		return true;
	}

	if current_line^ == end_line {
		return true;
	}

	for ; current_index^ < len(document_text); current_index^ += 1 {

		current := document_text[current_index^];

		if last^ == '\r' {
			current_line^ += 1;

			if current_line^ == end_line {
				last^ = current;
				current_index^ += 1;
				return true;
			}
		} else if current == '\n' {
			current_line^ += 1;

			if current_line^ == end_line {
				last^ = current;
				current_index^ += 1;
				return true;
			}
		}

		last^ = document_text[current_index^];
	}

	return false;
}

get_character_offset_u16_to_u8 :: proc (character_offset: int, document_text: []u8) -> int {

	utf8_idx  := 0;
	utf16_idx := 0;

	for utf16_idx < character_offset {

		r, w := utf8.decode_rune(document_text[utf8_idx:]);

		if r == '\n' {
			return utf8_idx;
		} else if w == 0 {
			return utf8_idx;
		} else if r < 0x10000 {
			utf16_idx += 1;
		} else {
			utf16_idx += 2;
		}

		utf8_idx += w;
	}

	return utf8_idx;
}

get_character_offset_u8_to_u16 :: proc (character_offset: int, document_text: []u8) -> int {

	utf8_idx  := 0;
	utf16_idx := 0;

	for utf8_idx < character_offset {

		r, w := utf8.decode_rune(document_text[utf8_idx:]);

		if r == '\n' {
			return utf16_idx;
		} else if w == 0 {
			return utf16_idx;
		} else if r < 0x10000 {
			utf16_idx += 1;
		} else {
			utf16_idx += 2;
		}

		utf8_idx += w;
	}

	return utf16_idx;
}

get_end_line_u16 :: proc (document_text: []u8) -> int {

	utf8_idx  := 0;
	utf16_idx := 0;

	for utf8_idx < len(document_text) {
		r, w := utf8.decode_rune(document_text[utf8_idx:]);

		if r == '\n' {
			return utf16_idx;
		} else if w == 0 {
			return utf16_idx;
		} else if r < 0x10000 {
			utf16_idx += 1;
		} else {
			utf16_idx += 2;
		}

		utf8_idx += w;
	}

	return utf16_idx;
}