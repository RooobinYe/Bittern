package fileio

import (
	"crypto/rand"
	"crypto/sha256"
	"io"
	"os"
	"path/filepath"
	"testing"
)

var testKey = []byte("0123456789abcdef")

func writeTemp(t *testing.T, data []byte) string {
	t.Helper()
	f, err := os.CreateTemp("", "sm4test-*")
	if err != nil {
		t.Fatalf("创建临时文件失败: %v", err)
	}
	defer f.Close()
	if _, err = f.Write(data); err != nil {
		t.Fatalf("写入临时文件失败: %v", err)
	}
	return f.Name()
}

func sha256File(t *testing.T, path string) []byte {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("打开文件失败: %v", err)
	}
	defer f.Close()
	h := sha256.New()
	if _, err = io.Copy(h, f); err != nil {
		t.Fatalf("计算 hash 失败: %v", err)
	}
	return h.Sum(nil)
}

func testRoundTrip(t *testing.T, mode byte, modeName string, plaintext []byte) {
	t.Helper()
	dir := t.TempDir()

	inputPath := writeTemp(t, plaintext)
	defer os.Remove(inputPath)

	encPath := filepath.Join(dir, "encrypted")
	decPath := filepath.Join(dir, "decrypted")

	if err := EncryptFile(inputPath, encPath, testKey, mode, nil); err != nil {
		t.Fatalf("[%s] 加密失败: %v", modeName, err)
	}
	if err := DecryptFile(encPath, decPath, testKey, nil); err != nil {
		t.Fatalf("[%s] 解密失败: %v", modeName, err)
	}

	origHash := sha256File(t, inputPath)
	decHash := sha256File(t, decPath)
	if string(origHash) != string(decHash) {
		t.Fatalf("[%s] 解密后文件 hash 不一致", modeName)
	}
}

func TestEncryptDecrypt_CBC_Small(t *testing.T) {
	testRoundTrip(t, ModeCBC, "CBC", []byte("Hello, SM4 File Encryption!"))
}

func TestEncryptDecrypt_CFB_Small(t *testing.T) {
	testRoundTrip(t, ModeCFB, "CFB", []byte("Hello, SM4 File Encryption!"))
}

func TestEncryptDecrypt_CBC_Empty(t *testing.T) {
	testRoundTrip(t, ModeCBC, "CBC-empty", []byte{})
}

func TestEncryptDecrypt_CFB_Empty(t *testing.T) {
	testRoundTrip(t, ModeCFB, "CFB-empty", []byte{})
}

func TestEncryptDecrypt_CBC_1MB(t *testing.T) {
	data := make([]byte, 1024*1024)
	if _, err := rand.Read(data); err != nil {
		t.Fatalf("生成随机数据失败: %v", err)
	}
	testRoundTrip(t, ModeCBC, "CBC-1MB", data)
}

func TestEncryptDecrypt_CFB_NonAligned(t *testing.T) {
	data := make([]byte, 100)
	for i := range data {
		data[i] = byte(i)
	}
	testRoundTrip(t, ModeCFB, "CFB-nonaligned", data)
}

func TestDecrypt_WrongKey(t *testing.T) {
	dir := t.TempDir()
	input := writeTemp(t, []byte("secret content"))
	defer os.Remove(input)
	enc := filepath.Join(dir, "enc")
	dec := filepath.Join(dir, "dec")

	if err := EncryptFile(input, enc, testKey, ModeCBC, nil); err != nil {
		t.Fatalf("加密失败: %v", err)
	}
	wrongKey := []byte("fedcba9876543210")
	err := DecryptFile(enc, dec, wrongKey, nil)
	// CBC 错误密钥应产生 PKCS#7 填充错误
	if err == nil {
		t.Fatal("错误密钥解密应返回错误")
	}
}

func TestDecrypt_InvalidMagic(t *testing.T) {
	dir := t.TempDir()
	// 写入一个头部 magic 错误的文件
	badFile := filepath.Join(dir, "bad")
	garbage := make([]byte, 64)
	for i := range garbage {
		garbage[i] = byte(i + 1)
	}
	if err := os.WriteFile(badFile, garbage, 0644); err != nil {
		t.Fatalf("写入测试文件失败: %v", err)
	}
	err := DecryptFile(badFile, filepath.Join(dir, "out"), testKey, nil)
	if err == nil {
		t.Fatal("无效文件头应返回错误")
	}
}

func TestEncrypt_InvalidKeyLength(t *testing.T) {
	input := writeTemp(t, []byte("data"))
	defer os.Remove(input)
	err := EncryptFile(input, "/tmp/out_invalid", []byte("short"), ModeCBC, nil)
	if err == nil {
		t.Fatal("非法密钥长度应返回错误")
	}
}

func TestEncrypt_ProgressCallback(t *testing.T) {
	dir := t.TempDir()
	data := make([]byte, 256*1024)
	if _, err := rand.Read(data); err != nil {
		t.Fatalf("生成随机数据失败: %v", err)
	}
	input := writeTemp(t, data)
	defer os.Remove(input)

	var lastProcessed int64
	callback := func(processed, total int64) {
		lastProcessed = processed
	}

	enc := filepath.Join(dir, "enc")
	if err := EncryptFile(input, enc, testKey, ModeCBC, callback); err != nil {
		t.Fatalf("加密失败: %v", err)
	}
	if lastProcessed == 0 {
		t.Fatal("进度回调未被调用")
	}
}
