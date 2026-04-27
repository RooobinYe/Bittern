package crypto

import (
	"crypto/rand"
	"errors"
	"io"
)

// EncryptCBC 使用 SM4-CBC 模式加密明文，返回 (iv, ciphertext, error)。
// IV 由函数内部随机生成；密文已包含 PKCS#7 填充。
func EncryptCBC(key, plaintext []byte) (iv, ciphertext []byte, err error) {
	if len(key) != KeySize {
		return nil, nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}

	iv = make([]byte, BlockSize)
	if _, err = io.ReadFull(rand.Reader, iv); err != nil {
		return nil, nil, errors.New("生成随机 IV 失败")
	}

	padded := pkcs7Pad(plaintext, BlockSize)
	ciphertext = make([]byte, len(padded))
	prev := iv

	for i := 0; i < len(padded); i += BlockSize {
		block := make([]byte, BlockSize)
		for j := 0; j < BlockSize; j++ {
			block[j] = padded[i+j] ^ prev[j]
		}
		enc, e := encryptBlock(key, block)
		if e != nil {
			return nil, nil, e
		}
		copy(ciphertext[i:], enc)
		prev = ciphertext[i : i+BlockSize]
	}
	return iv, ciphertext, nil
}

// DecryptCBC 使用 SM4-CBC 模式解密密文，返回原始明文（已去除 PKCS#7 填充）。
func DecryptCBC(key, iv, ciphertext []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}
	if len(iv) != BlockSize {
		return nil, errors.New("IV 长度必须为 16 字节")
	}
	if len(ciphertext) == 0 || len(ciphertext)%BlockSize != 0 {
		return nil, errors.New("密文长度无效，可能文件已损坏或密钥错误")
	}

	plaintext := make([]byte, len(ciphertext))
	prev := iv

	for i := 0; i < len(ciphertext); i += BlockSize {
		dec, e := decryptBlock(key, ciphertext[i:i+BlockSize])
		if e != nil {
			return nil, e
		}
		for j := 0; j < BlockSize; j++ {
			plaintext[i+j] = dec[j] ^ prev[j]
		}
		prev = ciphertext[i : i+BlockSize]
	}

	return pkcs7Unpad(plaintext, BlockSize)
}
