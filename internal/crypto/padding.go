package crypto

import (
	"errors"
	"fmt"
)

// pkcs7Pad 对数据进行 PKCS#7 填充至 blockSize 的整数倍。
func pkcs7Pad(data []byte, blockSize int) []byte {
	padding := blockSize - len(data)%blockSize
	padded := make([]byte, len(data)+padding)
	copy(padded, data)
	for i := len(data); i < len(padded); i++ {
		padded[i] = byte(padding)
	}
	return padded
}

// pkcs7Unpad 去除 PKCS#7 填充并返回原始数据。
func pkcs7Unpad(data []byte, blockSize int) ([]byte, error) {
	if len(data) == 0 {
		return nil, errors.New("数据长度为零，无法去填充")
	}
	if len(data)%blockSize != 0 {
		return nil, fmt.Errorf("数据长度 %d 不是块大小 %d 的整数倍", len(data), blockSize)
	}
	padding := int(data[len(data)-1])
	if padding == 0 || padding > blockSize {
		return nil, fmt.Errorf("无效的 PKCS#7 填充字节：%d", padding)
	}
	for i := len(data) - padding; i < len(data); i++ {
		if data[i] != byte(padding) {
			return nil, errors.New("PKCS#7 填充字节不一致，密钥或数据可能有误")
		}
	}
	return data[:len(data)-padding], nil
}
