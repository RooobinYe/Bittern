package crypto

import (
	"crypto/rand"
	"errors"
	"io"
)

// EncryptCTR 使用 SM4-CTR 模式加密明文，返回 (iv, ciphertext, error)。
// CTR 为流密码模式，无需填充，明文长度任意。
// 加密公式：C_i = P_i ⊕ E_K(counter_i)，counter_0 = IV，每块大端 +1
// 加解密对称：DecryptCTR 与 EncryptCTR 算法相同。
func EncryptCTR(key, plaintext []byte) (iv, ciphertext []byte, err error) {
	if len(key) != KeySize {
		return nil, nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}

	iv = make([]byte, BlockSize)
	if _, err = io.ReadFull(rand.Reader, iv); err != nil {
		return nil, nil, errors.New("生成随机 IV 失败")
	}

	ciphertext, err = ctrXOR(key, iv, plaintext)
	if err != nil {
		return nil, nil, err
	}
	return iv, ciphertext, nil
}

// DecryptCTR 使用 SM4-CTR 模式解密密文，返回原始明文。
// CTR 加解密结构对称，解密即用相同 keystream 再异或一次。
func DecryptCTR(key, iv, ciphertext []byte) ([]byte, error) {
	if len(key) != KeySize {
		return nil, errors.New("密钥长度必须为 16 字节（128 bit）")
	}
	if len(iv) != BlockSize {
		return nil, errors.New("IV 长度必须为 16 字节")
	}
	return ctrXOR(key, iv, ciphertext)
}

// ctrXOR 是 CTR 加解密的公共内核：
// 用 counter 流（IV 起始、每块大端 +1）经 SM4 加密生成 keystream，与 input 逐字节 XOR。
func ctrXOR(key, iv, input []byte) ([]byte, error) {
	counter := make([]byte, BlockSize)
	copy(counter, iv)

	out := make([]byte, len(input))
	for i := 0; i < len(input); {
		keystream, e := encryptBlock(key, counter)
		if e != nil {
			return nil, e
		}
		n := BlockSize
		if remaining := len(input) - i; remaining < n {
			n = remaining
		}
		for j := 0; j < n; j++ {
			out[i+j] = input[i+j] ^ keystream[j]
		}
		incCounter(counter)
		i += n
	}
	return out, nil
}

// incCounter 将 16 字节 counter 视为大端整数并 +1。
func incCounter(c []byte) {
	for i := len(c) - 1; i >= 0; i-- {
		c[i]++
		if c[i] != 0 {
			return
		}
	}
}
