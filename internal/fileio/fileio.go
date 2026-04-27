package fileio

import (
	"bufio"
	"bytes"
	"errors"
	"io"
	"os"

	"bittern/internal/crypto"
)

const chunkSize = 64 * 1024 // 64 KB

// ProgressCallback 进度回调：processed = 已处理字节，total = 文件总字节（0 表示未知）。
type ProgressCallback func(processed, total int64)

// EncryptFile 读取 input 文件，使用 key 和指定 mode（ModeCBC / ModeCTR）加密后写入 output。
// progress 可为 nil。
func EncryptFile(input, output string, key []byte, mode byte, progress ProgressCallback) error {
	if len(key) != crypto.KeySize {
		return errors.New("密钥长度必须为 16 字节（128 bit）")
	}
	if mode != ModeCBC && mode != ModeCTR {
		return errors.New("不支持的加密模式，请选择 CBC 或 CTR")
	}

	in, err := os.Open(input)
	if err != nil {
		return errors.New("无法打开输入文件：" + err.Error())
	}
	defer in.Close()

	stat, err := in.Stat()
	if err != nil {
		return errors.New("无法获取文件信息：" + err.Error())
	}
	totalSize := stat.Size()

	// 读取全部明文（对于超大文件可改为流式，但本阶段 CBC/CTR 需要整体加密再写头）
	plaintext, err := io.ReadAll(bufio.NewReaderSize(in, chunkSize))
	if err != nil {
		return errors.New("读取文件失败：" + err.Error())
	}

	var iv, ciphertext []byte
	switch mode {
	case ModeCBC:
		iv, ciphertext, err = crypto.EncryptCBC(key, plaintext)
	case ModeCTR:
		iv, ciphertext, err = crypto.EncryptCTR(key, plaintext)
	}
	if err != nil {
		return errors.New("加密失败：" + err.Error())
	}

	out, err := os.Create(output)
	if err != nil {
		return errors.New("无法创建输出文件：" + err.Error())
	}
	defer out.Close()

	bw := bufio.NewWriterSize(out, chunkSize)

	var ivArr [IVSize]byte
	copy(ivArr[:], iv)
	if err = writeHeader(bw, Header{Mode: mode, IV: ivArr}); err != nil {
		return errors.New("写入文件头失败：" + err.Error())
	}

	var written int64
	reader := bytes.NewReader(ciphertext)
	buf := make([]byte, chunkSize)
	for {
		n, readErr := reader.Read(buf)
		if n > 0 {
			if _, writeErr := bw.Write(buf[:n]); writeErr != nil {
				return errors.New("写入密文失败：" + writeErr.Error())
			}
			written += int64(n)
			if progress != nil {
				progress(written, totalSize)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return errors.New("处理密文时出错：" + readErr.Error())
		}
	}

	if err = bw.Flush(); err != nil {
		return errors.New("刷新输出缓冲区失败：" + err.Error())
	}
	return nil
}

// DecryptFile 读取加密文件 input，解密后写入 output。
// 自动从文件头解析 Mode 和 IV，无需外部传入。
// progress 可为 nil。
func DecryptFile(input, output string, key []byte, progress ProgressCallback) error {
	if len(key) != crypto.KeySize {
		return errors.New("密钥长度必须为 16 字节（128 bit）")
	}

	in, err := os.Open(input)
	if err != nil {
		return errors.New("无法打开加密文件：" + err.Error())
	}
	defer in.Close()

	stat, err := in.Stat()
	if err != nil {
		return errors.New("无法获取文件信息：" + err.Error())
	}
	totalSize := stat.Size()

	br := bufio.NewReaderSize(in, chunkSize)

	header, err := readHeader(br)
	if err != nil {
		return err
	}

	ciphertext, err := io.ReadAll(br)
	if err != nil {
		return errors.New("读取密文失败：" + err.Error())
	}

	var plaintext []byte
	switch header.Mode {
	case ModeCBC:
		plaintext, err = crypto.DecryptCBC(key, header.IV[:], ciphertext)
	case ModeCTR:
		plaintext, err = crypto.DecryptCTR(key, header.IV[:], ciphertext)
	}
	if err != nil {
		return errors.New("解密失败，密钥可能不正确：" + err.Error())
	}

	out, err := os.Create(output)
	if err != nil {
		return errors.New("无法创建输出文件：" + err.Error())
	}
	defer out.Close()

	bw := bufio.NewWriterSize(out, chunkSize)
	var written int64
	reader := bytes.NewReader(plaintext)
	buf := make([]byte, chunkSize)
	for {
		n, readErr := reader.Read(buf)
		if n > 0 {
			if _, writeErr := bw.Write(buf[:n]); writeErr != nil {
				return errors.New("写入明文失败：" + writeErr.Error())
			}
			written += int64(n)
			if progress != nil {
				progress(written, totalSize)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return errors.New("处理明文时出错：" + readErr.Error())
		}
	}

	if err = bw.Flush(); err != nil {
		return errors.New("刷新输出缓冲区失败：" + err.Error())
	}
	return nil
}
