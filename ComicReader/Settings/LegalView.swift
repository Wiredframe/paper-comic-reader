//
//  LegalView.swift
//  Comic Reader
//
//  The About / Legal screens: Terms of Use, Privacy Policy and the (MIT) licence.
//  All text is static and bundled — nothing is fetched.
//

import SwiftUI

/// A plain scrollable legal document.
struct LegalTextView: View {
    let title: String
    let body_: String

    var body: some View {
        ScrollView {
            Text(body_)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum Legal {
    static let holder = "Ulf Schuster (Wiredframe)"
    static let year = "2026"

    static let terms = """
    Terms of Use

    Paper Comic Reader is a personal comic-reading app. By downloading, installing or using \
    it, you agree to these terms. If you do not agree, do not use the app.

    The App
    Paper Comic Reader lets you import and read comic files you already own. You are \
    responsible for the files you add and for having the right to use them. The app \
    does not provide, sell or distribute any comics.

    "As Is", No Warranty
    The app is provided "as is" and "as available", without warranty of any kind, \
    express or implied, including but not limited to merchantability, fitness for a \
    particular purpose and non-infringement. You use the app at your own risk. To the \
    maximum extent permitted by law, the developer is not liable for any loss or \
    damage — including lost or corrupted files — arising from your use of the app.

    Developer's Rights
    The developer may change, update, suspend or discontinue the app, or any part of \
    it, at any time and without notice, and may modify these terms. Continued use \
    after a change means you accept the updated terms.

    Purchases
    The app may offer optional, one-time in-app purchases ("tips") that support \
    development and unlock no additional functionality. Purchases are handled by the \
    App Store and are subject to Apple's terms.

    Governing Law
    These terms are governed by the laws of the Federal Republic of Germany, without \
    regard to conflict-of-law rules.
    """

    static let privacy = """
    Privacy Policy

    Short version: Paper Comic Reader collects nothing.

    No data collection
    The app has no analytics, no tracking, no accounts and no ads. The developer does \
    not collect, receive, store or share any personal data about you.

    Your content stays on your device
    The comics you import, your reading progress, bookmarks and settings are stored \
    only on your device (and in your own iCloud backup, if you have one enabled for \
    the device). They are never uploaded to the developer or any third party.

    In-app purchases
    Optional tips are processed by Apple through the App Store. The developer never \
    sees your payment details. Apple's own privacy policy applies to those \
    transactions.

    Contact
    Questions about privacy? Email accounts@wiredframe.de.
    """

    static var license: String {
        """
        MIT License

        Copyright (c) \(year) \(holder)

        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """
    }

    /// Third-party open-source components. The unrar paragraph below is reproduced
    /// verbatim as its licence requires (must include the full paragraph starting
    /// from "UnRAR source code").
    static let acknowledgements = """
    Acknowledgements

    Paper Comic Reader is built with the following open-source components. Thank you to \
    their authors.

    ZIPFoundation — MIT License
    Copyright (c) 2017-2025 Thomas Zoechling
    Reads CBZ (ZIP) comic archives.

    UnrarKit — BSD 2-Clause License
    Copyright (c) Abbey Code (Christopher Anderson) and contributors
    An Objective-C wrapper for reading CBR (RAR) comic archives.

    unrar — UnRAR License
    All copyrights to RAR and the utility UnRAR are exclusively owned by the author, \
    Alexander Roshal. Paper Comic Reader includes unrar source code to decode RAR archives. \
    Per its licence:

    UnRAR source code may be used in any software to handle RAR archives without \
    limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible \
    archiver and to re-create RAR compression algorithm, which is proprietary. \
    Distribution of modified UnRAR source code in separate form or as a part of other \
    software is permitted, provided that full text of this paragraph, starting from \
    "UnRAR source code" words, is included in license, or in documentation if license \
    is not available, and in source code comments of resulting package.

    The RAR archiver and the UnRAR utility are distributed "as is". No warranty of any \
    kind is expressed or implied.

    Full license texts are available from each project's repository.
    """
}
