//
//  Typography.swift
//  PiCode
//
//  The app's one reading size.
//
//  The sidebar's menu of chats and projects, the transcript's content and the
//  composer's text are all the same kind of thing — text read and typed at the
//  keyboard — so they are all the same size. It is an explicit point size rather
//  than a semantic style because the styles disagree: measured on macOS, `.body`
//  and `.headline` resolve to 13pt but `.callout` resolves to 12 and
//  `.subheadline` to 11, so "use `.body` here and `.callout` there" quietly
//  produces three sizes. Change `baseSize` and every surface follows.
//
//  Metadata — timestamps, badges, pills, captions — is deliberately *not* this
//  size. It is not what is being read; it is what is being referred to.
//

import SwiftUI

enum Typography {
    /// The one size for anything the user reads or types: menu rows, message
    /// content, code, and the composer.
    static let baseSize: CGFloat = 13

    /// Prose. Regular weight, because a size is not a weight.
    static let body = Font.system(size: baseSize, weight: .regular)

    /// Prose that has to carry a little emphasis — a tool name, a label inside
    /// content. Bold is reserved for first-level headings.
    static let bodySemibold = Font.system(size: baseSize, weight: .semibold)

    /// Code, commands, paths and JSON: the same size as prose, in monospace.
    static let code = Font.system(size: baseSize, design: .monospaced)
}
