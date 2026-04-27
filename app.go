package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"time"

	"bittern/internal/fileio"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App struct
type App struct {
	ctx context.Context
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// EncryptRequest 前端加密请求参数
type EncryptRequest struct {
	InputPath  string `json:"inputPath"`
	OutputPath string `json:"outputPath"`
	KeyHex     string `json:"keyHex"`
	Mode       string `json:"mode"` // "CBC" 或 "CTR"
}

// EncryptResult 加密操作结果
type EncryptResult struct {
	Success        bool   `json:"success"`
	ElapsedMs      int64  `json:"elapsedMs"`
	BytesProcessed int64  `json:"bytesProcessed"`
	Message        string `json:"message"`
}

// DecryptRequest 前端解密请求参数
type DecryptRequest struct {
	InputPath  string `json:"inputPath"`
	OutputPath string `json:"outputPath"`
	KeyHex     string `json:"keyHex"`
}

// DecryptResult 解密操作结果
type DecryptResult struct {
	Success        bool   `json:"success"`
	ElapsedMs      int64  `json:"elapsedMs"`
	BytesProcessed int64  `json:"bytesProcessed"`
	Message        string `json:"message"`
}

// BenchmarkResult 单次基准测试结果
type BenchmarkResult struct {
	Mode             string  `json:"mode"`
	EncryptMs        int64   `json:"encryptMs"`
	DecryptMs        int64   `json:"decryptMs"`
	ThroughputMBps   float64 `json:"throughputMBps"`
}

// progressPayload 进度事件数据
type progressPayload struct {
	Processed int64 `json:"processed"`
	Total     int64 `json:"total"`
}

// parseKeyHex 将 32 字符 hex 字符串解码为 16 字节密钥。
func parseKeyHex(keyHex string) ([]byte, error) {
	if len(keyHex) != 32 {
		return nil, errors.New("密钥长度不正确，需为 32 个十六进制字符（128 bit）")
	}
	key, err := hex.DecodeString(keyHex)
	if err != nil {
		return nil, errors.New("密钥格式错误，请确认为合法的十六进制字符串")
	}
	return key, nil
}

// parseModeStr 将字符串模式转换为 fileio 模式常量。
func parseModeStr(mode string) (byte, error) {
	switch mode {
	case "CBC":
		return fileio.ModeCBC, nil
	case "CTR":
		return fileio.ModeCTR, nil
	default:
		return 0, fmt.Errorf("不支持的加密模式「%s」，请选择 CBC 或 CTR", mode)
	}
}

// SelectInputFile 打开文件选择对话框，返回用户选择的文件路径。
func (a *App) SelectInputFile() (string, error) {
	path, err := runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{
		Title: "选择要加解密的文件",
	})
	if err != nil {
		return "", errors.New("打开文件对话框失败")
	}
	return path, nil
}

// SelectOutputFile 打开保存文件对话框，返回用户选择的输出路径。
func (a *App) SelectOutputFile(defaultName string) (string, error) {
	path, err := runtime.SaveFileDialog(a.ctx, runtime.SaveDialogOptions{
		Title:           "选择输出文件路径",
		DefaultFilename: defaultName,
	})
	if err != nil {
		return "", errors.New("打开保存对话框失败")
	}
	return path, nil
}

// GenerateKey 生成 16 字节随机密钥并以 hex 字符串返回。
func (a *App) GenerateKey() (string, error) {
	key := make([]byte, 16)
	if _, err := rand.Read(key); err != nil {
		return "", errors.New("生成随机密钥失败")
	}
	return hex.EncodeToString(key), nil
}

// EncryptFile 对文件进行 SM4 加密，通过 encrypt:progress 事件推送进度。
func (a *App) EncryptFile(req EncryptRequest) (EncryptResult, error) {
	key, err := parseKeyHex(req.KeyHex)
	if err != nil {
		return EncryptResult{}, err
	}
	mode, err := parseModeStr(req.Mode)
	if err != nil {
		return EncryptResult{}, err
	}

	stat, err := os.Stat(req.InputPath)
	if err != nil {
		return EncryptResult{}, errors.New("输入文件不存在或无法访问")
	}
	totalSize := stat.Size()

	progress := func(processed, total int64) {
		runtime.EventsEmit(a.ctx, "encrypt:progress", progressPayload{
			Processed: processed,
			Total:     total,
		})
	}

	start := time.Now()
	if err = fileio.EncryptFile(req.InputPath, req.OutputPath, key, mode, progress); err != nil {
		return EncryptResult{}, err
	}
	elapsed := time.Since(start).Milliseconds()

	return EncryptResult{
		Success:        true,
		ElapsedMs:      elapsed,
		BytesProcessed: totalSize,
		Message:        fmt.Sprintf("加密完成，耗时 %d ms", elapsed),
	}, nil
}

// DecryptFile 对 SM4 加密文件解密，通过 decrypt:progress 事件推送进度。
func (a *App) DecryptFile(req DecryptRequest) (DecryptResult, error) {
	key, err := parseKeyHex(req.KeyHex)
	if err != nil {
		return DecryptResult{}, err
	}

	stat, err := os.Stat(req.InputPath)
	if err != nil {
		return DecryptResult{}, errors.New("输入文件不存在或无法访问")
	}
	totalSize := stat.Size()

	progress := func(processed, total int64) {
		runtime.EventsEmit(a.ctx, "decrypt:progress", progressPayload{
			Processed: processed,
			Total:     total,
		})
	}

	start := time.Now()
	if err = fileio.DecryptFile(req.InputPath, req.OutputPath, key, progress); err != nil {
		return DecryptResult{}, err
	}
	elapsed := time.Since(start).Milliseconds()

	return DecryptResult{
		Success:        true,
		ElapsedMs:      elapsed,
		BytesProcessed: totalSize,
		Message:        fmt.Sprintf("解密完成，耗时 %d ms", elapsed),
	}, nil
}

// RunBenchmark 对给定大小的随机数据运行 CBC 和 CTR 的加解密基准测试。
// sizeLabel: "1KB" / "1MB" / "10MB" / "100MB"
func (a *App) RunBenchmark(sizeLabel string) ([]BenchmarkResult, error) {
	sizeMap := map[string]int{
		"1KB":   1024,
		"1MB":   1024 * 1024,
		"10MB":  10 * 1024 * 1024,
		"100MB": 100 * 1024 * 1024,
	}
	size, ok := sizeMap[sizeLabel]
	if !ok {
		return nil, fmt.Errorf("不支持的测试规格「%s」，可选：1KB / 1MB / 10MB / 100MB", sizeLabel)
	}

	// 生成随机密钥和数据
	key := make([]byte, 16)
	if _, err := rand.Read(key); err != nil {
		return nil, errors.New("生成随机密钥失败")
	}
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return nil, errors.New("生成随机测试数据失败")
	}

	results := make([]BenchmarkResult, 0, 2)
	for _, spec := range []struct {
		name string
		mode byte
	}{
		{"CBC", fileio.ModeCBC},
		{"CTR", fileio.ModeCTR},
	} {
		// 创建临时文件
		tmpIn, err := os.CreateTemp("", "bm-in-*")
		if err != nil {
			return nil, errors.New("创建基准测试临时文件失败")
		}
		tmpIn.Write(data)
		tmpIn.Close()
		defer os.Remove(tmpIn.Name())

		tmpEnc, err := os.CreateTemp("", "bm-enc-*")
		if err != nil {
			return nil, errors.New("创建基准测试临时文件失败")
		}
		tmpEnc.Close()
		defer os.Remove(tmpEnc.Name())

		tmpDec, err := os.CreateTemp("", "bm-dec-*")
		if err != nil {
			return nil, errors.New("创建基准测试临时文件失败")
		}
		tmpDec.Close()
		defer os.Remove(tmpDec.Name())

		// 加密计时
		encStart := time.Now()
		if err = fileio.EncryptFile(tmpIn.Name(), tmpEnc.Name(), key, spec.mode, nil); err != nil {
			return nil, fmt.Errorf("%s 加密基准测试失败：%w", spec.name, err)
		}
		encMs := time.Since(encStart).Milliseconds()

		// 解密计时
		keyHex := hex.EncodeToString(key)
		_ = keyHex
		decStart := time.Now()
		if err = fileio.DecryptFile(tmpEnc.Name(), tmpDec.Name(), key, nil); err != nil {
			return nil, fmt.Errorf("%s 解密基准测试失败：%w", spec.name, err)
		}
		decMs := time.Since(decStart).Milliseconds()

		// 计算加密吞吐率（MB/s）
		var throughput float64
		if encMs > 0 {
			throughput = float64(size) / (float64(encMs) / 1000.0) / (1024 * 1024)
		}

		results = append(results, BenchmarkResult{
			Mode:           spec.name,
			EncryptMs:      encMs,
			DecryptMs:      decMs,
			ThroughputMBps: throughput,
		})
	}
	return results, nil
}
