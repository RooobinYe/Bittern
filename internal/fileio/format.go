// 加密文件头格式：Magic(4B) | Mode(1B) | IV(16B) | Ciphertext(...)
// Magic: "SM4\x00"
// Mode:  0x01 = CBC, 0x02 = CTR

package fileio

import (
	"encoding/binary"
	"errors"
	"io"
)

const (
	MagicSize  = 4
	ModeSize   = 1
	IVSize     = 16
	HeaderSize = MagicSize + ModeSize + IVSize // 21 字节

	ModeCBC byte = 0x01
	ModeCTR byte = 0x02
)

var magic = [MagicSize]byte{'S', 'M', '4', 0x00}

// Header 表示加密文件头。
type Header struct {
	Mode byte
	IV   [IVSize]byte
}

// writeHeader 将文件头写入 w。
func writeHeader(w io.Writer, h Header) error {
	if _, err := w.Write(magic[:]); err != nil {
		return err
	}
	if err := binary.Write(w, binary.BigEndian, h.Mode); err != nil {
		return err
	}
	_, err := w.Write(h.IV[:])
	return err
}

// readHeader 从 r 读取并校验文件头，返回 Header。
func readHeader(r io.Reader) (Header, error) {
	var buf [HeaderSize]byte
	if _, err := io.ReadFull(r, buf[:]); err != nil {
		return Header{}, errors.New("读取文件头失败，文件可能不是有效的加密文件")
	}
	if buf[0] != magic[0] || buf[1] != magic[1] || buf[2] != magic[2] || buf[3] != magic[3] {
		return Header{}, errors.New("文件头 Magic 不匹配，请确认选择的是正确的加密文件")
	}
	mode := buf[MagicSize]
	if mode != ModeCBC && mode != ModeCTR {
		return Header{}, errors.New("未知的加密模式，文件头可能已损坏")
	}
	var h Header
	h.Mode = mode
	copy(h.IV[:], buf[MagicSize+ModeSize:])
	return h, nil
}
