package crypto

import (
	"crypto/rand"
	"errors"
	"io"
)

// EncryptCFB 使用 SM4-CFB 模式加密明文，返回 (iv, ciphertext, error)。
// CFB 为流密码模式，无需填充，明文长度任意。
// 加密公式：C_i = P_i ⊕ E_K(C_{i-1})，C_0 = IV
func EncryptCFB(key, plaintext []byte) (iv, ciphertext []byte, err error) {
	if len(key) != KeySize {
		return nil, nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}

	iv = make([]byte, BlockSize)
	if _, err = io.ReadFull(rand.Reader, iv); err != nil {
		return nil, nil, errors.New("生成随机 IV 失败")
	}

	ciphertext = make([]byte, len(plaintext))
	prev := iv

	for i := 0; i < len(plaintext); {
		keystream, e := encryptBlock(key, prev)
		if e != nil {
			return nil, nil, e
		}
		// 本块处理字节数（最后一块可能不足 BlockSize）
		n := BlockSize
		if remaining := len(plaintext) - i; remaining < n {
			n = remaining
		}
		for j := 0; j < n; j++ {
			ciphertext[i+j] = plaintext[i+j] ^ keystream[j]
		}
		// 构造下一轮反馈块：当本块不足 16 字节时，使用 ciphertext 对应字节 + keystream 剩余字节
		nextPrev := make([]byte, BlockSize)
		copy(nextPrev, keystream)
		for j := 0; j < n; j++ {
			nextPrev[j] = ciphertext[i+j]
		}
		prev = nextPrev
		i += n
	}
	return iv, ciphertext, nil
}

// DecryptCFB 使用 SM4-CFB 模式解密密文，返回原始明文。
// 解密公式：P_i = C_i ⊕ E_K(C_{i-1})，C_0 = IV
func DecryptCFB(key, iv, ciphertext []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}
	if len(iv) != BlockSize {
		return nil, errors.New("IV 长度必须为 16 字节")
	}

	plaintext := make([]byte, len(ciphertext))
	prev := iv

	for i := 0; i < len(ciphertext); {
		keystream, e := encryptBlock(key, prev)
		if e != nil {
			return nil, e
		}
		n := BlockSize
		if remaining := len(ciphertext) - i; remaining < n {
			n = remaining
		}
		for j := 0; j < n; j++ {
			plaintext[i+j] = ciphertext[i+j] ^ keystream[j]
		}
		nextPrev := make([]byte, BlockSize)
		copy(nextPrev, keystream)
		for j := 0; j < n; j++ {
			nextPrev[j] = ciphertext[i+j]
		}
		prev = nextPrev
		i += n
	}
	return plaintext, nil
}
