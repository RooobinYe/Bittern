package crypto

import (
	"bytes"
	"crypto/rand"
	"testing"
)

var testKey = []byte("0123456789abcdef") // 16 字节密钥

// --- CBC 测试 ---

func TestCBC_EncryptDecrypt(t *testing.T) {
	plaintext := []byte("Hello SM4 CBC mode!")
	iv, ct, err := EncryptCBC(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCBC 失败: %v", err)
	}
	pt, err := DecryptCBC(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCBC 失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatalf("CBC 解密结果不匹配: got %q, want %q", pt, plaintext)
	}
}

func TestCBC_EmptyInput(t *testing.T) {
	iv, ct, err := EncryptCBC(testKey, []byte{})
	if err != nil {
		t.Fatalf("EncryptCBC 空输入失败: %v", err)
	}
	pt, err := DecryptCBC(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCBC 空输入失败: %v", err)
	}
	if len(pt) != 0 {
		t.Fatalf("空输入解密后应为空，got len=%d", len(pt))
	}
}

func TestCBC_WrongKey(t *testing.T) {
	plaintext := []byte("secret data")
	iv, ct, err := EncryptCBC(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCBC 失败: %v", err)
	}
	wrongKey := []byte("fedcba9876543210")
	pt, err := DecryptCBC(wrongKey, iv, ct)
	// 错误密钥应导致解密失败（填充校验失败）或结果不等
	if err == nil && bytes.Equal(pt, plaintext) {
		t.Fatal("错误密钥不应解密出正确结果")
	}
}

func TestCBC_InvalidKeyLength(t *testing.T) {
	_, _, err := EncryptCBC([]byte("short"), []byte("data"))
	if err == nil {
		t.Fatal("非法密钥长度应返回错误")
	}
}

func TestCBC_ExactBlockSize(t *testing.T) {
	// 正好 16 字节明文，会填充一整块
	plaintext := []byte("1234567890abcdef")
	iv, ct, err := EncryptCBC(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCBC 失败: %v", err)
	}
	pt, err := DecryptCBC(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCBC 失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatal("整块明文 CBC 解密结果不匹配")
	}
}

// --- CFB 测试 ---

func TestCFB_EncryptDecrypt(t *testing.T) {
	plaintext := []byte("Hello SM4 CFB mode!")
	iv, ct, err := EncryptCFB(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCFB 失败: %v", err)
	}
	pt, err := DecryptCFB(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCFB 失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatalf("CFB 解密结果不匹配: got %q, want %q", pt, plaintext)
	}
}

func TestCFB_EmptyInput(t *testing.T) {
	iv, ct, err := EncryptCFB(testKey, []byte{})
	if err != nil {
		t.Fatalf("EncryptCFB 空输入失败: %v", err)
	}
	pt, err := DecryptCFB(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCFB 空输入失败: %v", err)
	}
	if len(pt) != 0 {
		t.Fatalf("空输入解密后应为空，got len=%d", len(pt))
	}
}

func TestCFB_WrongKey(t *testing.T) {
	plaintext := []byte("secret data")
	iv, ct, err := EncryptCFB(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCFB 失败: %v", err)
	}
	wrongKey := []byte("fedcba9876543210")
	pt, err := DecryptCFB(wrongKey, iv, ct)
	if err == nil && bytes.Equal(pt, plaintext) {
		t.Fatal("错误密钥不应解密出正确结果")
	}
}

func TestCFB_NonBlockAligned(t *testing.T) {
	// 非块对齐长度（如 25 字节）
	plaintext := make([]byte, 25)
	for i := range plaintext {
		plaintext[i] = byte(i)
	}
	iv, ct, err := EncryptCFB(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCFB 失败: %v", err)
	}
	pt, err := DecryptCFB(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCFB 失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatal("非对齐 CFB 解密结果不匹配")
	}
}

func TestCFB_InvalidKeyLength(t *testing.T) {
	_, _, err := EncryptCFB([]byte("short"), []byte("data"))
	if err == nil {
		t.Fatal("非法密钥长度应返回错误")
	}
}

// --- 大文件测试 ---

func TestCBC_LargeFile(t *testing.T) {
	plaintext := make([]byte, 1024*1024) // 1 MB
	if _, err := rand.Read(plaintext); err != nil {
		t.Fatalf("生成随机数据失败: %v", err)
	}
	iv, ct, err := EncryptCBC(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCBC 大文件失败: %v", err)
	}
	pt, err := DecryptCBC(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCBC 大文件失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatal("大文件 CBC 解密结果不匹配")
	}
}

func TestCFB_LargeFile(t *testing.T) {
	plaintext := make([]byte, 1024*1024) // 1 MB
	if _, err := rand.Read(plaintext); err != nil {
		t.Fatalf("生成随机数据失败: %v", err)
	}
	iv, ct, err := EncryptCFB(testKey, plaintext)
	if err != nil {
		t.Fatalf("EncryptCFB 大文件失败: %v", err)
	}
	pt, err := DecryptCFB(testKey, iv, ct)
	if err != nil {
		t.Fatalf("DecryptCFB 大文件失败: %v", err)
	}
	if !bytes.Equal(pt, plaintext) {
		t.Fatal("大文件 CFB 解密结果不匹配")
	}
}

// --- 基准测试 ---

func makeData(size int) []byte {
	b := make([]byte, size)
	_, _ = rand.Read(b)
	return b
}

func BenchmarkCBC_Encrypt_1KB(b *testing.B)  { benchCBCEncrypt(b, 1024) }
func BenchmarkCBC_Encrypt_1MB(b *testing.B)  { benchCBCEncrypt(b, 1024*1024) }
func BenchmarkCBC_Encrypt_10MB(b *testing.B) { benchCBCEncrypt(b, 10*1024*1024) }

func benchCBCEncrypt(b *testing.B, size int) {
	data := makeData(size)
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = EncryptCBC(testKey, data)
	}
}

func BenchmarkCFB_Encrypt_1KB(b *testing.B)  { benchCFBEncrypt(b, 1024) }
func BenchmarkCFB_Encrypt_1MB(b *testing.B)  { benchCFBEncrypt(b, 1024*1024) }
func BenchmarkCFB_Encrypt_10MB(b *testing.B) { benchCFBEncrypt(b, 10*1024*1024) }

func benchCFBEncrypt(b *testing.B, size int) {
	data := makeData(size)
	b.SetBytes(int64(size))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _, _ = EncryptCFB(testKey, data)
	}
}

func BenchmarkCBC_Decrypt_1MB(b *testing.B) {
	data := makeData(1024 * 1024)
	iv, ct, _ := EncryptCBC(testKey, data)
	b.SetBytes(int64(len(ct)))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = DecryptCBC(testKey, iv, ct)
	}
}

func BenchmarkCFB_Decrypt_1MB(b *testing.B) {
	data := makeData(1024 * 1024)
	iv, ct, _ := EncryptCFB(testKey, data)
	b.SetBytes(int64(len(ct)))
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = DecryptCFB(testKey, iv, ct)
	}
}
