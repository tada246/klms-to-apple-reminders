#!/usr/bin/env swift
// アプリアイコンの生成スクリプト。
//
// 原画（1024×1024 の正方形 PNG）を macOS 標準アイコンのテンプレに載せて、
// AppIcon.appiconset の 10 サイズを書き出す。
//   - 1024px のキャンバスに 824×824 の角丸の本体を中央配置（周囲 100px は透明マージン）
//   - 角丸半径は本体の約 22.4%
//   - 本体の下にやわらかい影
//
// 使い方（リポジトリのルートで）:
//   swift scripts/make-app-icon.swift [原画 PNG] [出力先 appiconset]
//   既定: design/icon/AppIcon-source.png → klms-to-apple-reminders/Assets.xcassets/AppIcon.appiconset
//
// 絵柄を作り直すとき（Figma など）は design/icon/AppIcon-source.png を差し替えて再実行するだけでよい。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let sourcePath = arguments.count > 1 ? arguments[1] : "design/icon/AppIcon-source.png"
let outputDir  = arguments.count > 2 ? arguments[2] : "klms-to-apple-reminders/Assets.xcassets/AppIcon.appiconset"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("原画を読み込めません: \(sourcePath)")
}
guard artwork.width == 1024, artwork.height == 1024 else {
    fail("原画は 1024×1024 である必要があります（実際: \(artwork.width)×\(artwork.height)）")
}

/// (ファイル名, ピクセル数)。Contents.json の size × scale に対応する。
let outputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024),
]

func render(pixels: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("描画コンテキストを作れません") }

    ctx.interpolationQuality = .high
    let scale = CGFloat(pixels) / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let radius = body.width * 0.2237
    let shape = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 影（本体と同じ形を塗って影だけ残し、その上に絵柄を重ねる）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 22 * scale,
                  color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 絵柄を角丸でクリップして本体に敷き詰める
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(artwork, in: body)
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { fail("画像を生成できません") }
    return image
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for output in outputs {
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(output.name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("書き出し先を作れません: \(url.path)")
    }
    CGImageDestinationAddImage(destination, render(pixels: output.pixels), nil)
    guard CGImageDestinationFinalize(destination) else { fail("書き出しに失敗: \(url.path)") }
    print("wrote \(output.name) (\(output.pixels)px)")
}
