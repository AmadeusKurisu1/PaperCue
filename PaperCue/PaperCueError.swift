//
//  PaperCueError.swift
//  PaperCue
//
//  Created by Codex on 2026/5/11.
//

import Foundation

enum PaperCueError: LocalizedError, Equatable {
    case emptyExtractedText
    case invalidURL
    case missingAPIKey
    case invalidBaseURL
    case unsupportedResponse
    case invalidGeneratedPayload(message: String)
    case lowQualityWebContent
    case serverError(statusCode: Int, message: String)
    case requestTimedOut(seconds: Int)
    case networkUnavailable(message: String)
    case ocrFailed(message: String)
    case persistenceFailed(message: String)
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .emptyExtractedText:
            "没有提取到可复制文本。v1 暂不支持扫描件或 OCR。"
        case .invalidURL:
            "请输入有效的网页地址。"
        case .missingAPIKey:
            "请先在设置里填写 API key。"
        case .invalidBaseURL:
            "Base URL 无效。"
        case .unsupportedResponse:
            "模型返回格式无法解析，请检查模型或兼容接口设置。"
        case let .invalidGeneratedPayload(message):
            "模型返回的学习材料不完整：\(message)"
        case .lowQualityWebContent:
            "没有从网页中识别到足够可信的正文内容。请换用文章正文页、PDF，或复制正文后重试。"
        case let .serverError(statusCode, message):
            "模型服务返回 \(statusCode)：\(message)"
        case let .requestTimedOut(seconds):
            "模型请求超时（\(seconds) 秒）。这通常是网络、模型响应较慢或输入文本过长导致的；可以换用更快的模型、减少文本长度，或稍后重试。"
        case let .networkUnavailable(message):
            "无法连接模型服务：\(message)"
        case let .ocrFailed(message):
            "没有提取到可复制文本，OCR 也未能识别正文：\(message)"
        case let .persistenceFailed(message):
            "保存失败：\(message)"
        case .exportFailed:
            "导出 Anki 文件失败。"
        }
    }
}

extension Error {
    var paperCueMessage: String {
        if let localizedError = self as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return localizedDescription
    }
}
