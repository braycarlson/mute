package buffer

import "bytes"

type CircularBuffer struct {
	data []byte
	size int
	head int
	tail int
}

func NewCircularBuffer(size int) *CircularBuffer {
	return &CircularBuffer{
		data: make([]byte, size),
		size: size,
	}
}

func (buffer *CircularBuffer) Push(key byte) {
	buffer.data[buffer.tail] = key
	buffer.tail = (buffer.tail + 1) % buffer.size

	if buffer.tail == buffer.head {
		buffer.head = (buffer.head + 1) % buffer.size
	}
}

func (buffer *CircularBuffer) AsSlice() []byte {
	if buffer.tail >= buffer.head {
		return buffer.data[buffer.head:buffer.tail]
	}

	return append(
		buffer.data[buffer.head:buffer.size],
		buffer.data[:buffer.tail]...,
	)
}

func (buffer *CircularBuffer) IsMatch(hotkey []byte) bool {
	if len(buffer.AsSlice()) < len(hotkey) {
		return false
	}

	var subsection []byte
	subsection = buffer.AsSlice()[len(buffer.AsSlice())-len(hotkey):]

	return bytes.Equal(subsection, hotkey)
}
