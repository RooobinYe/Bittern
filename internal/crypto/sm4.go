// SM4 算法封装（使用 github.com/tjfoc/gmsm/sm4）
//
// SM4 算法结构要点：
//   - 分组长度 128 bit（16 字节），密钥长度 128 bit
//   - 32 轮非线性迭代；解密使用加密轮密钥的逆序
//   - 密钥扩展（KeyExpansion）：原始密钥 XOR 系统参数 FK，再经 32 轮 T' 变换生成轮密钥 rk[0..31]
//   - 轮函数 F：X_{i+4} = X_i ⊕ T(X_{i+1} ⊕ X_{i+2} ⊕ X_{i+3} ⊕ rk_i)
//   - 合成置换 T = L ∘ τ：τ 为 4 个并行 S 盒替换；L 为线性变换（循环移位 XOR）

package crypto

import (
	gmsm4 "github.com/tjfoc/gmsm/sm4"
)

const (
	BlockSize = 16 // SM4 分组大小（字节）
	KeySize   = 16 // SM4 密钥大小（字节）
)

// encryptBlock 使用 SM4 对单个 16 字节块加密。
func encryptBlock(key, src []byte) ([]byte, error) {
	c, err := gmsm4.NewCipher(key)
	if err != nil {
		return nil, err
	}
	dst := make([]byte, BlockSize)
	c.Encrypt(dst, src)
	return dst, nil
}

// decryptBlock 使用 SM4 对单个 16 字节块解密。
func decryptBlock(key, src []byte) ([]byte, error) {
	c, err := gmsm4.NewCipher(key)
	if err != nil {
		return nil, err
	}
	dst := make([]byte, BlockSize)
	c.Decrypt(dst, src)
	return dst, nil
}
