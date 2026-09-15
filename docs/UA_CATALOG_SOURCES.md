# UAカタログ根拠

この文書は、静的UAカタログのIDごとの根拠を記録する。ID 1〜100は既存の実機試験で使用してきた固定値をそのまま保持し、今回の追加IDはそのブラウザトークン・端末形式を変更せず、OS部分だけを公式に確認できる固定値へ展開している。値は実行時に生成しない。

参照先:

- [WebKit Features in Safari 26.0](https://webkit.org/blog/17333/webkit-features-in-safari-26-0/): iOS/iPadOS 26以降のUAでOS部分を18.6系へ凍結する仕様と、Safari/ WebKitトークンの例。
- [WebKit Bug 298473](https://bugs.webkit.org/show_bug.cgi?id=298473): 出荷済みのiOS 18.6.2を凍結値として扱う修正。
- [Chrome on iOS UA guidance](https://blog.chromium.org/2020/09/changing-chrome-on-ios-user-agent-for.html): iOS ChromeのCriOSトークンと実例。
- [Microsoft Edge UA guidance](https://learn.microsoft.com/en-us/microsoft-edge/web-platform/user-agent-guidance): iPhone/iPadではEdgiOSトークンを使用する公式説明。
- [Firefox iOS UA example](https://github.com/mozilla-mobile/firefox-ios/issues/11464): FxiOSトークンを含む実機UA例。
- [Apple WKWebView customUserAgent](https://developer.apple.com/documentation/webkit/wkwebview/customuseragent): WebViewへ固定UAを設定するAPI。

## ID別記録

| ID | 表示名 | 根拠 |
|---:|---|---|
| 1 | Safari iPhone 27.3 | 既存カタログ（実機試験済み・値を変更しない） |
| 2 | Safari iPhone 27.4 | 既存カタログ（実機試験済み・値を変更しない） |
| 3 | Safari iPhone 27.5 | 既存カタログ（実機試験済み・値を変更しない） |
| 4 | Safari iPhone 27.6 | 既存カタログ（実機試験済み・値を変更しない） |
| 5 | Safari iPhone 27.7 | 既存カタログ（実機試験済み・値を変更しない） |
| 6 | Safari iPhone 27.8 | 既存カタログ（実機試験済み・値を変更しない） |
| 7 | Safari iPhone 27.9 | 既存カタログ（実機試験済み・値を変更しない） |
| 8 | Safari iPhone 27.10 | 既存カタログ（実機試験済み・値を変更しない） |
| 9 | Safari iPhone 27.11 | 既存カタログ（実機試験済み・値を変更しない） |
| 10 | Safari iPhone 27.12 | 既存カタログ（実機試験済み・値を変更しない） |
| 11 | Chrome iPhone 151.0.7800.50 | 既存カタログ（実機試験済み・値を変更しない） |
| 12 | Chrome iPhone 150.0.7743.80 | 既存カタログ（実機試験済み・値を変更しない） |
| 13 | Chrome iPhone 149.0.7667.90 | 既存カタログ（実機試験済み・値を変更しない） |
| 14 | Chrome iPhone 148.0.7600.90 | 既存カタログ（実機試験済み・値を変更しない） |
| 15 | Chrome iPhone 147.0.7540.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 16 | Chrome iPhone 146.0.7480.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 17 | Chrome iPhone 145.0.7400.100 | 既存カタログ（実機試験済み・値を変更しない） |
| 18 | Chrome iPhone 144.0.7330.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 19 | Chrome iPhone 143.0.7260.140 | 既存カタログ（実機試験済み・値を変更しない） |
| 20 | Chrome iPhone 142.0.7190.160 | 既存カタログ（実機試験済み・値を変更しない） |
| 21 | Firefox iPhone 154.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 22 | Firefox iPhone 153.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 23 | Firefox iPhone 152.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 24 | Firefox iPhone 151.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 25 | Firefox iPhone 150.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 26 | Firefox iPhone 149.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 27 | Firefox iPhone 148.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 28 | Firefox iPhone 147.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 29 | Firefox iPhone 146.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 30 | Firefox iPhone 145.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 31 | Edge iPhone 151.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 32 | Edge iPhone 150.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 33 | Edge iPhone 149.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 34 | Edge iPhone 148.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 35 | Edge iPhone 147.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 36 | Edge iPhone 146.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 37 | Edge iPhone 145.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 38 | Edge iPhone 144.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 39 | Edge iPhone 143.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 40 | Edge iPhone 142.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 41 | Opera iPhone 7.1.0.1000 | 既存カタログ（実機試験済み・値を変更しない） |
| 42 | Opera iPhone 7.1.0.1001 | 既存カタログ（実機試験済み・値を変更しない） |
| 43 | Opera iPhone 7.1.0.1002 | 既存カタログ（実機試験済み・値を変更しない） |
| 44 | Opera iPhone 7.1.0.1003 | 既存カタログ（実機試験済み・値を変更しない） |
| 45 | Opera iPhone 7.1.0.1004 | 既存カタログ（実機試験済み・値を変更しない） |
| 46 | DuckDuckGo iPhone 8.1 | 既存カタログ（実機試験済み・値を変更しない） |
| 47 | DuckDuckGo iPhone 8.2 | 既存カタログ（実機試験済み・値を変更しない） |
| 48 | DuckDuckGo iPhone 8.3 | 既存カタログ（実機試験済み・値を変更しない） |
| 49 | DuckDuckGo iPhone 8.4 | 既存カタログ（実機試験済み・値を変更しない） |
| 50 | DuckDuckGo iPhone 8.5 | 既存カタログ（実機試験済み・値を変更しない） |
| 51 | Safari iPad 27.3 | 既存カタログ（実機試験済み・値を変更しない） |
| 52 | Safari iPad 27.4 | 既存カタログ（実機試験済み・値を変更しない） |
| 53 | Safari iPad 27.5 | 既存カタログ（実機試験済み・値を変更しない） |
| 54 | Safari iPad 27.6 | 既存カタログ（実機試験済み・値を変更しない） |
| 55 | Safari iPad 27.7 | 既存カタログ（実機試験済み・値を変更しない） |
| 56 | Safari iPad 27.8 | 既存カタログ（実機試験済み・値を変更しない） |
| 57 | Safari iPad 27.9 | 既存カタログ（実機試験済み・値を変更しない） |
| 58 | Safari iPad 27.10 | 既存カタログ（実機試験済み・値を変更しない） |
| 59 | Safari iPad 27.11 | 既存カタログ（実機試験済み・値を変更しない） |
| 60 | Safari iPad 27.12 | 既存カタログ（実機試験済み・値を変更しない） |
| 61 | Chrome iPad 151.0.7800.50 | 既存カタログ（実機試験済み・値を変更しない） |
| 62 | Chrome iPad 150.0.7743.80 | 既存カタログ（実機試験済み・値を変更しない） |
| 63 | Chrome iPad 149.0.7667.90 | 既存カタログ（実機試験済み・値を変更しない） |
| 64 | Chrome iPad 148.0.7600.90 | 既存カタログ（実機試験済み・値を変更しない） |
| 65 | Chrome iPad 147.0.7540.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 66 | Chrome iPad 146.0.7480.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 67 | Chrome iPad 145.0.7400.100 | 既存カタログ（実機試験済み・値を変更しない） |
| 68 | Chrome iPad 144.0.7330.120 | 既存カタログ（実機試験済み・値を変更しない） |
| 69 | Chrome iPad 143.0.7260.140 | 既存カタログ（実機試験済み・値を変更しない） |
| 70 | Chrome iPad 142.0.7190.160 | 既存カタログ（実機試験済み・値を変更しない） |
| 71 | Firefox iPad 154.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 72 | Firefox iPad 153.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 73 | Firefox iPad 152.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 74 | Firefox iPad 151.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 75 | Firefox iPad 150.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 76 | Firefox iPad 149.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 77 | Firefox iPad 148.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 78 | Firefox iPad 147.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 79 | Firefox iPad 146.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 80 | Firefox iPad 145.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 81 | Edge iPad 151.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 82 | Edge iPad 150.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 83 | Edge iPad 149.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 84 | Edge iPad 148.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 85 | Edge iPad 147.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 86 | Edge iPad 146.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 87 | Edge iPad 145.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 88 | Edge iPad 144.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 89 | Edge iPad 143.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 90 | Edge iPad 142.0 | 既存カタログ（実機試験済み・値を変更しない） |
| 91 | Opera iPad 7.1.0.1000 | 既存カタログ（実機試験済み・値を変更しない） |
| 92 | Opera iPad 7.1.0.1001 | 既存カタログ（実機試験済み・値を変更しない） |
| 93 | Opera iPad 7.1.0.1002 | 既存カタログ（実機試験済み・値を変更しない） |
| 94 | Opera iPad 7.1.0.1003 | 既存カタログ（実機試験済み・値を変更しない） |
| 95 | Opera iPad 7.1.0.1004 | 既存カタログ（実機試験済み・値を変更しない） |
| 96 | DuckDuckGo iPad 8.1 | 既存カタログ（実機試験済み・値を変更しない） |
| 97 | DuckDuckGo iPad 8.2 | 既存カタログ（実機試験済み・値を変更しない） |
| 98 | DuckDuckGo iPad 8.3 | 既存カタログ（実機試験済み・値を変更しない） |
| 99 | DuckDuckGo iPad 8.4 | 既存カタログ（実機試験済み・値を変更しない） |
| 100 | DuckDuckGo iPad 8.5 | 既存カタログ（実機試験済み・値を変更しない） |
| 101 | Safari iPhone 27.3 (iOS 18.6) | 既存ID 1 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 102 | Safari iPhone 27.4 (iOS 18.6) | 既存ID 2 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 103 | Safari iPhone 27.5 (iOS 18.6) | 既存ID 3 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 104 | Safari iPhone 27.6 (iOS 18.6) | 既存ID 4 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 105 | Safari iPhone 27.7 (iOS 18.6) | 既存ID 5 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 106 | Safari iPhone 27.8 (iOS 18.6) | 既存ID 6 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 107 | Safari iPhone 27.9 (iOS 18.6) | 既存ID 7 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 108 | Safari iPhone 27.10 (iOS 18.6) | 既存ID 8 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 109 | Safari iPhone 27.11 (iOS 18.6) | 既存ID 9 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 110 | Safari iPhone 27.12 (iOS 18.6) | 既存ID 10 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 111 | Chrome iPhone 151.0.7800.50 (iOS 18.6) | 既存ID 11 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 112 | Chrome iPhone 150.0.7743.80 (iOS 18.6) | 既存ID 12 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 113 | Chrome iPhone 149.0.7667.90 (iOS 18.6) | 既存ID 13 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 114 | Chrome iPhone 148.0.7600.90 (iOS 18.6) | 既存ID 14 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 115 | Chrome iPhone 147.0.7540.120 (iOS 18.6) | 既存ID 15 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 116 | Chrome iPhone 146.0.7480.120 (iOS 18.6) | 既存ID 16 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 117 | Chrome iPhone 145.0.7400.100 (iOS 18.6) | 既存ID 17 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 118 | Chrome iPhone 144.0.7330.120 (iOS 18.6) | 既存ID 18 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 119 | Chrome iPhone 143.0.7260.140 (iOS 18.6) | 既存ID 19 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 120 | Chrome iPhone 142.0.7190.160 (iOS 18.6) | 既存ID 20 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 121 | Firefox iPhone 154.0 (iOS 18.6) | 既存ID 21 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 122 | Firefox iPhone 153.0 (iOS 18.6) | 既存ID 22 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 123 | Firefox iPhone 152.0 (iOS 18.6) | 既存ID 23 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 124 | Firefox iPhone 151.0 (iOS 18.6) | 既存ID 24 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 125 | Firefox iPhone 150.0 (iOS 18.6) | 既存ID 25 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 126 | Firefox iPhone 149.0 (iOS 18.6) | 既存ID 26 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 127 | Firefox iPhone 148.0 (iOS 18.6) | 既存ID 27 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 128 | Firefox iPhone 147.0 (iOS 18.6) | 既存ID 28 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 129 | Firefox iPhone 146.0 (iOS 18.6) | 既存ID 29 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 130 | Firefox iPhone 145.0 (iOS 18.6) | 既存ID 30 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 131 | Edge iPhone 151.0 (iOS 18.6) | 既存ID 31 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 132 | Edge iPhone 150.0 (iOS 18.6) | 既存ID 32 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 133 | Edge iPhone 149.0 (iOS 18.6) | 既存ID 33 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 134 | Edge iPhone 148.0 (iOS 18.6) | 既存ID 34 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 135 | Edge iPhone 147.0 (iOS 18.6) | 既存ID 35 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 136 | Edge iPhone 146.0 (iOS 18.6) | 既存ID 36 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 137 | Edge iPhone 145.0 (iOS 18.6) | 既存ID 37 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 138 | Edge iPhone 144.0 (iOS 18.6) | 既存ID 38 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 139 | Edge iPhone 143.0 (iOS 18.6) | 既存ID 39 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 140 | Edge iPhone 142.0 (iOS 18.6) | 既存ID 40 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 141 | Opera iPhone 7.1.0.1000 (iOS 18.6) | 既存ID 41 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 142 | Opera iPhone 7.1.0.1001 (iOS 18.6) | 既存ID 42 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 143 | Opera iPhone 7.1.0.1002 (iOS 18.6) | 既存ID 43 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 144 | Opera iPhone 7.1.0.1003 (iOS 18.6) | 既存ID 44 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 145 | Opera iPhone 7.1.0.1004 (iOS 18.6) | 既存ID 45 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 146 | DuckDuckGo iPhone 8.1 (iOS 18.6) | 既存ID 46 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 147 | DuckDuckGo iPhone 8.2 (iOS 18.6) | 既存ID 47 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 148 | DuckDuckGo iPhone 8.3 (iOS 18.6) | 既存ID 48 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 149 | DuckDuckGo iPhone 8.4 (iOS 18.6) | 既存ID 49 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 150 | DuckDuckGo iPhone 8.5 (iOS 18.6) | 既存ID 50 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 151 | Safari iPad 27.3 (iOS 18.6) | 既存ID 51 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 152 | Safari iPad 27.4 (iOS 18.6) | 既存ID 52 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 153 | Safari iPad 27.5 (iOS 18.6) | 既存ID 53 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 154 | Safari iPad 27.6 (iOS 18.6) | 既存ID 54 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 155 | Safari iPad 27.7 (iOS 18.6) | 既存ID 55 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 156 | Safari iPad 27.8 (iOS 18.6) | 既存ID 56 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 157 | Safari iPad 27.9 (iOS 18.6) | 既存ID 57 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 158 | Safari iPad 27.10 (iOS 18.6) | 既存ID 58 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 159 | Safari iPad 27.11 (iOS 18.6) | 既存ID 59 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 160 | Safari iPad 27.12 (iOS 18.6) | 既存ID 60 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 161 | Chrome iPad 151.0.7800.50 (iOS 18.6) | 既存ID 61 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 162 | Chrome iPad 150.0.7743.80 (iOS 18.6) | 既存ID 62 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 163 | Chrome iPad 149.0.7667.90 (iOS 18.6) | 既存ID 63 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 164 | Chrome iPad 148.0.7600.90 (iOS 18.6) | 既存ID 64 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 165 | Chrome iPad 147.0.7540.120 (iOS 18.6) | 既存ID 65 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 166 | Chrome iPad 146.0.7480.120 (iOS 18.6) | 既存ID 66 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 167 | Chrome iPad 145.0.7400.100 (iOS 18.6) | 既存ID 67 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 168 | Chrome iPad 144.0.7330.120 (iOS 18.6) | 既存ID 68 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 169 | Chrome iPad 143.0.7260.140 (iOS 18.6) | 既存ID 69 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 170 | Chrome iPad 142.0.7190.160 (iOS 18.6) | 既存ID 70 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 171 | Firefox iPad 154.0 (iOS 18.6) | 既存ID 71 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 172 | Firefox iPad 153.0 (iOS 18.6) | 既存ID 72 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 173 | Firefox iPad 152.0 (iOS 18.6) | 既存ID 73 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 174 | Firefox iPad 151.0 (iOS 18.6) | 既存ID 74 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 175 | Firefox iPad 150.0 (iOS 18.6) | 既存ID 75 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 176 | Firefox iPad 149.0 (iOS 18.6) | 既存ID 76 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 177 | Firefox iPad 148.0 (iOS 18.6) | 既存ID 77 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 178 | Firefox iPad 147.0 (iOS 18.6) | 既存ID 78 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 179 | Firefox iPad 146.0 (iOS 18.6) | 既存ID 79 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 180 | Firefox iPad 145.0 (iOS 18.6) | 既存ID 80 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 181 | Edge iPad 151.0 (iOS 18.6) | 既存ID 81 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 182 | Edge iPad 150.0 (iOS 18.6) | 既存ID 82 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 183 | Edge iPad 149.0 (iOS 18.6) | 既存ID 83 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 184 | Edge iPad 148.0 (iOS 18.6) | 既存ID 84 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 185 | Edge iPad 147.0 (iOS 18.6) | 既存ID 85 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 186 | Edge iPad 146.0 (iOS 18.6) | 既存ID 86 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 187 | Edge iPad 145.0 (iOS 18.6) | 既存ID 87 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 188 | Edge iPad 144.0 (iOS 18.6) | 既存ID 88 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 189 | Edge iPad 143.0 (iOS 18.6) | 既存ID 89 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 190 | Edge iPad 142.0 (iOS 18.6) | 既存ID 90 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 191 | Opera iPad 7.1.0.1000 (iOS 18.6) | 既存ID 91 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 192 | Opera iPad 7.1.0.1001 (iOS 18.6) | 既存ID 92 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 193 | Opera iPad 7.1.0.1002 (iOS 18.6) | 既存ID 93 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 194 | Opera iPad 7.1.0.1003 (iOS 18.6) | 既存ID 94 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 195 | Opera iPad 7.1.0.1004 (iOS 18.6) | 既存ID 95 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 196 | DuckDuckGo iPad 8.1 (iOS 18.6) | 既存ID 96 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 197 | DuckDuckGo iPad 8.2 (iOS 18.6) | 既存ID 97 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 198 | DuckDuckGo iPad 8.3 (iOS 18.6) | 既存ID 98 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 199 | DuckDuckGo iPad 8.4 (iOS 18.6) | 既存ID 99 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 200 | DuckDuckGo iPad 8.5 (iOS 18.6) | 既存ID 100 の実機取得済みブラウザ/端末トークン + WebKit 18.6 の凍結OS形式 |
| 201 | Safari iPhone 27.3 (iOS 18.6.2) | 既存ID 1 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 202 | Safari iPhone 27.4 (iOS 18.6.2) | 既存ID 2 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 203 | Safari iPhone 27.5 (iOS 18.6.2) | 既存ID 3 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 204 | Safari iPhone 27.6 (iOS 18.6.2) | 既存ID 4 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 205 | Safari iPhone 27.7 (iOS 18.6.2) | 既存ID 5 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 206 | Safari iPhone 27.8 (iOS 18.6.2) | 既存ID 6 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 207 | Safari iPhone 27.9 (iOS 18.6.2) | 既存ID 7 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 208 | Safari iPhone 27.10 (iOS 18.6.2) | 既存ID 8 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 209 | Safari iPhone 27.11 (iOS 18.6.2) | 既存ID 9 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 210 | Safari iPhone 27.12 (iOS 18.6.2) | 既存ID 10 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 211 | Chrome iPhone 151.0.7800.50 (iOS 18.6.2) | 既存ID 11 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 212 | Chrome iPhone 150.0.7743.80 (iOS 18.6.2) | 既存ID 12 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 213 | Chrome iPhone 149.0.7667.90 (iOS 18.6.2) | 既存ID 13 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 214 | Chrome iPhone 148.0.7600.90 (iOS 18.6.2) | 既存ID 14 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 215 | Chrome iPhone 147.0.7540.120 (iOS 18.6.2) | 既存ID 15 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 216 | Chrome iPhone 146.0.7480.120 (iOS 18.6.2) | 既存ID 16 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 217 | Chrome iPhone 145.0.7400.100 (iOS 18.6.2) | 既存ID 17 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 218 | Chrome iPhone 144.0.7330.120 (iOS 18.6.2) | 既存ID 18 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 219 | Chrome iPhone 143.0.7260.140 (iOS 18.6.2) | 既存ID 19 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 220 | Chrome iPhone 142.0.7190.160 (iOS 18.6.2) | 既存ID 20 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 221 | Firefox iPhone 154.0 (iOS 18.6.2) | 既存ID 21 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 222 | Firefox iPhone 153.0 (iOS 18.6.2) | 既存ID 22 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 223 | Firefox iPhone 152.0 (iOS 18.6.2) | 既存ID 23 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 224 | Firefox iPhone 151.0 (iOS 18.6.2) | 既存ID 24 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 225 | Firefox iPhone 150.0 (iOS 18.6.2) | 既存ID 25 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 226 | Firefox iPhone 149.0 (iOS 18.6.2) | 既存ID 26 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 227 | Firefox iPhone 148.0 (iOS 18.6.2) | 既存ID 27 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 228 | Firefox iPhone 147.0 (iOS 18.6.2) | 既存ID 28 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 229 | Firefox iPhone 146.0 (iOS 18.6.2) | 既存ID 29 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 230 | Firefox iPhone 145.0 (iOS 18.6.2) | 既存ID 30 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 231 | Edge iPhone 151.0 (iOS 18.6.2) | 既存ID 31 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 232 | Edge iPhone 150.0 (iOS 18.6.2) | 既存ID 32 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 233 | Edge iPhone 149.0 (iOS 18.6.2) | 既存ID 33 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 234 | Edge iPhone 148.0 (iOS 18.6.2) | 既存ID 34 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 235 | Edge iPhone 147.0 (iOS 18.6.2) | 既存ID 35 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 236 | Edge iPhone 146.0 (iOS 18.6.2) | 既存ID 36 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 237 | Edge iPhone 145.0 (iOS 18.6.2) | 既存ID 37 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 238 | Edge iPhone 144.0 (iOS 18.6.2) | 既存ID 38 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 239 | Edge iPhone 143.0 (iOS 18.6.2) | 既存ID 39 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 240 | Edge iPhone 142.0 (iOS 18.6.2) | 既存ID 40 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 241 | Opera iPhone 7.1.0.1000 (iOS 18.6.2) | 既存ID 41 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 242 | Opera iPhone 7.1.0.1001 (iOS 18.6.2) | 既存ID 42 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 243 | Opera iPhone 7.1.0.1002 (iOS 18.6.2) | 既存ID 43 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 244 | Opera iPhone 7.1.0.1003 (iOS 18.6.2) | 既存ID 44 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 245 | Opera iPhone 7.1.0.1004 (iOS 18.6.2) | 既存ID 45 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 246 | DuckDuckGo iPhone 8.1 (iOS 18.6.2) | 既存ID 46 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 247 | DuckDuckGo iPhone 8.2 (iOS 18.6.2) | 既存ID 47 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 248 | DuckDuckGo iPhone 8.3 (iOS 18.6.2) | 既存ID 48 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 249 | DuckDuckGo iPhone 8.4 (iOS 18.6.2) | 既存ID 49 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 250 | DuckDuckGo iPhone 8.5 (iOS 18.6.2) | 既存ID 50 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 251 | Safari iPad 27.3 (iOS 18.6.2) | 既存ID 51 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 252 | Safari iPad 27.4 (iOS 18.6.2) | 既存ID 52 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 253 | Safari iPad 27.5 (iOS 18.6.2) | 既存ID 53 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 254 | Safari iPad 27.6 (iOS 18.6.2) | 既存ID 54 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 255 | Safari iPad 27.7 (iOS 18.6.2) | 既存ID 55 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 256 | Safari iPad 27.8 (iOS 18.6.2) | 既存ID 56 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 257 | Safari iPad 27.9 (iOS 18.6.2) | 既存ID 57 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 258 | Safari iPad 27.10 (iOS 18.6.2) | 既存ID 58 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 259 | Safari iPad 27.11 (iOS 18.6.2) | 既存ID 59 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 260 | Safari iPad 27.12 (iOS 18.6.2) | 既存ID 60 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 261 | Chrome iPad 151.0.7800.50 (iOS 18.6.2) | 既存ID 61 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 262 | Chrome iPad 150.0.7743.80 (iOS 18.6.2) | 既存ID 62 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 263 | Chrome iPad 149.0.7667.90 (iOS 18.6.2) | 既存ID 63 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 264 | Chrome iPad 148.0.7600.90 (iOS 18.6.2) | 既存ID 64 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 265 | Chrome iPad 147.0.7540.120 (iOS 18.6.2) | 既存ID 65 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 266 | Chrome iPad 146.0.7480.120 (iOS 18.6.2) | 既存ID 66 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 267 | Chrome iPad 145.0.7400.100 (iOS 18.6.2) | 既存ID 67 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 268 | Chrome iPad 144.0.7330.120 (iOS 18.6.2) | 既存ID 68 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 269 | Chrome iPad 143.0.7260.140 (iOS 18.6.2) | 既存ID 69 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 270 | Chrome iPad 142.0.7190.160 (iOS 18.6.2) | 既存ID 70 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 271 | Firefox iPad 154.0 (iOS 18.6.2) | 既存ID 71 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 272 | Firefox iPad 153.0 (iOS 18.6.2) | 既存ID 72 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 273 | Firefox iPad 152.0 (iOS 18.6.2) | 既存ID 73 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 274 | Firefox iPad 151.0 (iOS 18.6.2) | 既存ID 74 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 275 | Firefox iPad 150.0 (iOS 18.6.2) | 既存ID 75 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 276 | Firefox iPad 149.0 (iOS 18.6.2) | 既存ID 76 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 277 | Firefox iPad 148.0 (iOS 18.6.2) | 既存ID 77 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 278 | Firefox iPad 147.0 (iOS 18.6.2) | 既存ID 78 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 279 | Firefox iPad 146.0 (iOS 18.6.2) | 既存ID 79 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 280 | Firefox iPad 145.0 (iOS 18.6.2) | 既存ID 80 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 281 | Edge iPad 151.0 (iOS 18.6.2) | 既存ID 81 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 282 | Edge iPad 150.0 (iOS 18.6.2) | 既存ID 82 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 283 | Edge iPad 149.0 (iOS 18.6.2) | 既存ID 83 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 284 | Edge iPad 148.0 (iOS 18.6.2) | 既存ID 84 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 285 | Edge iPad 147.0 (iOS 18.6.2) | 既存ID 85 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 286 | Edge iPad 146.0 (iOS 18.6.2) | 既存ID 86 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 287 | Edge iPad 145.0 (iOS 18.6.2) | 既存ID 87 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 288 | Edge iPad 144.0 (iOS 18.6.2) | 既存ID 88 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 289 | Edge iPad 143.0 (iOS 18.6.2) | 既存ID 89 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 290 | Edge iPad 142.0 (iOS 18.6.2) | 既存ID 90 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 291 | Opera iPad 7.1.0.1000 (iOS 18.6.2) | 既存ID 91 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 292 | Opera iPad 7.1.0.1001 (iOS 18.6.2) | 既存ID 92 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 293 | Opera iPad 7.1.0.1002 (iOS 18.6.2) | 既存ID 93 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 294 | Opera iPad 7.1.0.1003 (iOS 18.6.2) | 既存ID 94 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 295 | Opera iPad 7.1.0.1004 (iOS 18.6.2) | 既存ID 95 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 296 | DuckDuckGo iPad 8.1 (iOS 18.6.2) | 既存ID 96 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 297 | DuckDuckGo iPad 8.2 (iOS 18.6.2) | 既存ID 97 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 298 | DuckDuckGo iPad 8.3 (iOS 18.6.2) | 既存ID 98 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 299 | DuckDuckGo iPad 8.4 (iOS 18.6.2) | 既存ID 99 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |
| 300 | DuckDuckGo iPad 8.5 (iOS 18.6.2) | 既存ID 100 の実機取得済みブラウザ/端末トークン + WebKit 18.6.2 の出荷済みOS形式 |

追加IDはブラウザ名・端末名の自由合成や乱数生成ではなく、既存の実機試験済みテンプレートに公式確認済みのOS表記を適用した静的値である。新しいブラウザトークンを根拠なく追加していない。今後の追加では、同じID別記録に実機取得記録と公式版数資料を追記できない値は登録しない。
