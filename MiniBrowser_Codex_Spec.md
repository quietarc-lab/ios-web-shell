# MiniBrowser 実装仕様書

## 1. 目的

iPhone向けのごく小さなWeb閲覧アプリを作成する。

当面はURLを固定せず、一般的なWeb閲覧を行える軽量ブラウザとして実装する。
将来的には一部サイト専用に寄せる可能性がある。

最重要機能は以下の3つ。

1. User-Agent切り替え
2. 現在サイトのCookie破棄・再取得
3. 既存iOSショートカット「セルラー再接続」の実行

加えて、ブックマークレット、広告ブロック、外向きIPv4変更確認、デバッグログを備える。

---

# 2. 開発環境・配布前提

## 2.1 開発環境

- 開発PC: Windows 11
- Macは所有していない
- 実機: iPhone 14
- 対応OS: iOS 26以上
- Apple Developer Programには加入しない
- SideStore導入済み
- Developer Mode / LocalDevVPN / pairing file 設定済み
- SideStoreによる7日refresh確認済み
- GitHub ActionsのmacOS runnerでSwiftUIアプリのビルド実績あり
- XcodeGenを利用
- unsigned IPAを生成し、SideStore側で署名・インストールする

## 2.2 アプリ名

`MiniBrowser`

## 2.3 画面向き

縦画面のみ。

## 2.4 ビルド成果物

最終成果物名:

`MiniBrowser.ipa`

ZIPではなく、最終的にIPA単体として扱う。

---

# 3. UI基本構成

標準iOS風の簡素なUIとする。
装飾より機能性・可読性・軽さを優先する。

基本構成:

```text
┌────────────────────────────┐
│ ☆ │ https://example.com... │
├────────────────────────────┤
│                            │
│          WKWebView         │
│                            │
│                            │
│   [一時通知スタック領域]     │
├────────────────────────────┤
│ ← │ → │ ↻ │ UA │ Cookie │ AP │
└────────────────────────────┘
```

### 上部

- 左端: ブックマークボタン
- URL入力欄
- 読み込み中のみ小型スピナー
- 更新ボタン等は上部に追加しない

### 下部ツールバー

左から固定:

1. 戻る
2. 進む
3. 更新
4. UA
5. Cookie
6. AP

ボタンを増やしすぎない。

---

# 4. URL入力

## 4.1 基本

- URL専用
- 検索語入力には対応しない
- 初回起動時は空ページ + URL入力欄
- 2回目以降は最後に開いていたURLを自動復元
- URL欄は常時表示
- ページ遷移・リダイレクト後も現在の完全URLに追従
- `https://`、path、queryまで表示する
- ページタイトルは表示しない

## 4.2 入力補助

- URL欄タップ時に現在URLを全文選択
- iOS標準のコピー / ペースト / 選択 / すべて選択を利用可能
- ペーストしただけでは遷移しない
- キーボードの `Go` で開く
- `Go` 後はキーボードを閉じる
- キーボード上部に `完了` を追加し、URLを開かずキーボードだけ閉じられるようにする

## 4.3 スキーム補完

以下のように補完する。

```text
example.com
→ https://example.com

example.com/path
→ https://example.com/path

http://example.com
→ そのまま

https://example.com
→ そのまま
```

検索語として解釈しない。

---

# 5. WebView

SwiftUI + WKWebViewを使用する。

## 5.1 基本設定

- JavaScript: 常時ON
- persistent `WKWebsiteDataStore.default()` を使用
- Cookie / LocalStorage / WebKitサイトデータは通常時保持
- iOS標準AutoFillを許可
- 位置情報 / カメラ / マイク等はiOS標準権限フローに任せる
- Pull to Refreshなし
- ページ内検索なし
- 履歴一覧画面なし
- ファイルダウンロード機能はMVP対象外
- 音声 / 動画は標準WKWebView挙動に任せる

## 5.2 リンク

- `http` / `https`: アプリ内で開く
- `target="_blank"` / `window.open`: 新しいWebViewを作らず同じWebViewで開く
- `mailto:` / `tel:` / App Store等の外部スキーム: iOS側の外部アプリへ渡す

## 5.3 戻る / 進む

- `goBack()`
- `goForward()`
- 利用不可時はボタンをdisable
- UA切り替え時も履歴を維持する

## 5.4 更新

- `reload()`

## 5.5 読み込みタイムアウト

30秒。

30秒経過時:

1. `stopLoading()`
2. 赤い一時通知 `読み込みタイムアウト`
3. 詳細をデバッグログへ記録
4. 自動再試行しない

通常の読み込み失敗も:

- 赤通知 `読み込み失敗`
- 詳細ログ
- 自動再試行なし

---

# 6. User-Agent切り替え

## 6.1 個数

最大300個。既存ID 1〜100は維持し、追加UAは101以降の連番で固定文字列として管理する。根拠が揃わない場合は300未満を許容する。

## 6.2 UA内容

Codex側で、実在するiOS / iPadOS系ブラウザを基に妥当なUA文字列を最大300種用意する。起動時の動的生成は行わず、根拠をID単位で記録する。

例カテゴリ:

- Safari iPhone
- Chrome iPhone
- Firefox iPhone
- Edge iPhone
- Brave iPhone
- DuckDuckGo iPhone
- Opera系 iPhone
- Safari iPad
- Chrome iPad
- Firefox iPad

UA文字列は存在する実ブラウザを模したものとする。

Windows / Android UAは原則避ける。
WKWebView実体はWebKitのままであり、UAのみ変更する設計。

## 6.3 操作

ボタン表示例:

`UA 3/利用可能数`

押下時:

1. 次のUAへ変更
2. 現在ページをreload
3. Cookieは保持
4. LocalStorageも保持
5. 履歴も保持
6. 選択UA番号を永続保存
7. 読み込み完了までUAボタンを一時disable

循環:

`1 → 2 → ... → カタログ末尾 → 1`

## 6.4 通知

切替時のみ数秒表示:

`UA変更: Firefox iOS (3/利用可能数)`

## 6.5 アクセス規制時の輪番

自動投稿中に対象ホストから「アクセス規制中です」を受けたUAは、UA IDと検知時刻から7×24時間、端末内の自動輪番から除外する。

除外時はコメントとメモリ上の手書き画像を保持したまま、同一自動投稿セッションで未試行かつ除外されていない次のUAを選び、新しい世代の準備フローを開始する。利用可能なUAがなくなった場合は停止する。

UA切替はWebKitエンジンやIP、Cookieを匿名化するものではなく、提示するUAプロファイルの輪番を多様化するための機能である。

## 6.6 自動投稿中の追加分岐

自動投稿中に対象ホストから次の完全一致文言を受けた場合:

`連続投稿はもうしばらく時間を置いてからお願い致します。`

同じUAと保持中のフォームを使い、既存の投稿ボタンを一度だけ追加で押す。Cookie削除、ページ再読込、AP再接続、UA変更は行わない。追加試行後の既知エラーでは停止し、世代ごとの送信回数は最大4回とする。

成功通知色は緑系。

## 6.7 自動投稿中のスリープ抑止

自動投稿の準備・送信・同スレ連続の次サイクル待機・投稿受付後の反映確認が残っている間、アプリが前面のときだけiOSのアイドルタイマーを無効にする。完了・停止・画面が背景へ移ったときは必ず有効へ戻す。これは画面の自動スリープを抑止するもので、iOSのバックグラウンド実行時間を延長するものではない。

---

# 7. Cookie再取得

## 7.1 目的

現在表示中サイトに関連するCookieだけを破棄し、その後の再読み込みで新しいCookieが取得されたか確認する。

## 7.2 削除対象

現在ページに関連する:

- 現在ホスト
- 親ドメインに紐づくCookie

を対象とする。

例:

`img.example.com`

閲覧時に、

- `img.example.com`
- `.example.com`

等に関連するCookieを削除対象に含める。

他の無関係サイトのCookieは消さない。

## 7.3 削除しないもの

- LocalStorage
- その他の一般的Webサイトデータ

Cookieボタンで削除するのはCookieのみ。

## 7.4 処理手順

1. 現在URL / domain取得
2. `WKHTTPCookieStore` から削除前Cookie一覧を取得
3. 対象Cookieを特定
4. 対象Cookie削除
5. 現在ページをreload
6. reload後に再度Cookie一覧取得
7. 新しいCookieが取得できたか判定
8. 結果通知
9. 詳細ログ記録

処理完了までCookieボタンをdisableする。

## 7.5 成功判定

「Cookie削除操作が成功した」だけでは `Cookie再取得済み` と表示しない。

少なくとも、

- 削除前に対象Cookieが存在した
- 削除処理後に対象Cookieが消えた
- reload後に対象Cookieが再度確認できた

という状態を確認してから成功扱いにする。

Cookieの値そのものをログに残さない。

## 7.6 通知

例:

- 緑: `Cookie再取得済み`
- 赤: `Cookie再取得失敗`
- 黄: `Cookieなし`
- 黄: `Cookie確認失敗`

数秒表示し、自動消去。

---

# 8. AP / セルラー再接続

## 8.1 既存ショートカット

iOSショートカット名:

`セルラー再接続`

アプリ内でショートカット名変更機能は作らない。
設定画面自体もMVPでは作らない。

## 8.2 APボタン

下部ツールバーの `AP` ボタンから上記ショートカットを呼び出す。

## 8.3 期待挙動

理想:

```text
MiniBrowser
→ APボタン
→ セルラー再接続
→ MiniBrowserへ自動復帰
```

ショートカット実行後、MiniBrowserへ自動で戻るようにする。

MiniBrowser側にカスタムURL Schemeを定義する。

例:

`minibrowser://return`

既存ショートカット「セルラー再接続」の末尾でこのURL Schemeを開き、MiniBrowserへ戻す。

注意:
ショートカット実行時に完全無画面で済まない可能性があるため、少なくとも自動復帰を実現する。

## 8.4 復帰後

MiniBrowserへ戻った後、現在ページを自動reloadしない。

これは意図的仕様。

---

# 9. 外向きIPv4変更確認

## 9.1 目的

セルラー再接続前後で外向きIPv4が変化したかを確認し、表示する。

IPv4のみ対象。
IPv6はMVPでは判定しない。

## 9.2 処理

APボタン押下時:

1. 外向きIPv4取得
2. 取得結果を保持
3. `セルラー再接続` ショートカット実行
4. MiniBrowserへ自動復帰
5. 回線復旧を待つ
6. 外向きIPv4再取得
7. 前後比較
8. 通知
9. ログ記録

AP処理中はAPボタンをdisable。

## 9.3 IP取得サービス

外部HTTPSサービスを利用して、現在の外向きIPv4を取得する。

実装時に、安定していてシンプルなIPv4確認用HTTPS endpointを選定する。
依存先はコード上で差し替えやすくする。

タイムアウトも設定する。

## 9.4 表示

IPは伏せない。

例:

`IP変更済み 106.72.10.15 → 126.33.44.51`

通知:

- 緑: `IP変更済み ...`
- 黄: `IP変更なし`
- 黄または赤: `IP確認失敗`

---

# 10. 一時通知UI

画面下部ツールバー直上に表示する。

複数通知が同時発生した場合、同じ位置へ重ならず、縦方向にstackする。

例:

```text
Cookie再取得済み
IP変更済み 106.72.10.15 → 126.33.44.51
```

## 色

- 成功: 緑
- 失敗: 赤
- 注意 / 確認不能: 黄

## 挙動

- 数秒表示
- 個別に自動消去
- Web閲覧を大きく邪魔しない
- modal dialogは原則使わない

---

# 11. 広告ブロック

## 11.1 基本

常時ON。

切り替えボタンなし。
設定画面なし。

WKWebViewの `WKContentRuleList` / Content Blocker系機能を利用する。

## 11.2 方針

- 軽量
- 保守的
- 代表的な広告 / tracker domainをブロック
- ページ本体を壊しにくい
- uBlock Origin完全互換等は目指さない
- JavaScript injectionで大量のDOM後処理を行う方式より、WebKit側content ruleを優先

## 11.3 例外

MVPでユーザー向け例外設定UIは作らない。

ただし内部設計は、将来

`このドメインだけ広告ブロック対象外`

を追加しやすい構造にする。

---

# 12. ブックマーク / ブックマークレット

## 12.1 呼び出し

URL欄左端に小さなブックマークボタン。

押すとブックマーク一覧を表示。

一覧表示中も背後のWebView状態は保持する。

## 12.2 保存内容

各項目:

- 名前
- URLまたはJavaScript本文
- 種別判定可能な形式
- 並び順

通常URLとブックマークレットを同じ一覧で管理する。

## 12.3 操作

通常タップ:

- URL → 開く
- Bookmarklet → 現在WebView上で実行

長押し:

- 編集

左スワイプ:

- 削除

長押しドラッグ:

- 並び替え
- 並び順を永続保存

## 12.4 新規追加

一覧画面に `＋`。

追加方法:

1. 新規URL / Bookmarkletを手入力
2. `現在ページを追加`

## 12.5 Bookmarklet本文

長文・複数行を前提にする。

- 実質的な文字数制限を設けない
- 大きめの複数行text editor
- 行折り返し
- コピー / ペースト / 全選択対応
- 保存内容は省略しない
- 端末内に永続保存
- iCloud同期なし
- export機能なし

## 12.6 実行

`javascript:` 形式は、単純URL navigationではなく、JavaScript本文を抽出し `evaluateJavaScript` で実行することを基本とする。

実行後:

- ブックマーク一覧を自動で閉じる
- Web画面へ戻る

成功時:

- 通知なし

失敗時:

- 赤い一時通知 `ブックマークレット実行失敗`
- 詳細ログ記録

## 12.7 構文チェック

保存時に可能な範囲で簡易構文チェック。

明らかなエラーがある場合:

- 黄色通知
- ただし保存自体は禁止しない

---

# 13. 永続保存

通常のアプリ更新後も保持する。

保存対象:

- 最後に開いていたURL
- 現在のUA番号
- Cookie
- LocalStorage
- WebKitの通常サイトデータ
- ブックマーク
- ブックマークレット
- 並び順
- デバッグログ

ブックマークは端末内保存のみ。

アプリ削除 → 再インストールで消えることは許容する。

---

# 14. デバッグログ

## 14.1 目的

問題発生時にユーザーがログをChatGPTへコピーして渡せるようにする。

通常画面にログを長々表示しない。

## 14.2 記録項目

必要に応じて以下を記録:

- 日時
- 操作種別
- 現在URL
- domain
- UA番号
- UA名
- Cookie削除前件数
- Cookie削除件数
- reload後Cookie件数
- Cookie再取得結果
- AP実行前IPv4
- AP実行後IPv4
- IP変更判定
- WebView読み込みエラー
- タイムアウト
- Bookmarklet実行エラー
- その他例外

## 14.3 記録禁止

以下はログへ残さない:

- Cookie value
- パスワード
- 認証token
- フォーム入力内容
- その他秘密情報

## 14.4 保持数

内部で直近500件程度を保持。
古いものから自動削除。

## 14.5 コピー

通常画面のアプリ名 / toolbarの空き部分等に長押しgestureを設定。

長押しメニュー:

`ログをコピー`

のみ。

押すと直近50件をplain textとしてclipboardへコピー。

例:

```text
2026-09-05 05:40:12
ACTION: Cookie Refresh
DOMAIN: example.com
UA: 3/300 Firefox iOS
COOKIE_BEFORE: 4
COOKIE_DELETED: 4
COOKIE_AFTER_RELOAD: 3
RESULT: SUCCESS

2026-09-05 05:41:03
ACTION: Cellular Reconnect
IP_BEFORE: 106.72.10.15
IP_AFTER: 126.33.44.51
RESULT: IP_CHANGED
```

---

# 15. エラー処理方針

UIは簡潔に保つ。

詳細はログへ記録し、ユーザー向けには短い通知のみ出す。

## 例

### Web読み込み

- `読み込み失敗`
- `読み込みタイムアウト`

### Cookie

- `Cookie再取得済み`
- `Cookie再取得失敗`
- `Cookieなし`
- `Cookie確認失敗`

### IP

- `IP変更済み x.x.x.x → y.y.y.y`
- `IP変更なし`
- `IP確認失敗`

### Bookmarklet

- `ブックマークレット実行失敗`

自動リトライは原則しない。

---

# 16. MVPに含めないもの

以下は不要。

- 検索エンジン
- 複数タブ
- 履歴一覧画面
- ページ内検索
- Pull to Refresh
- ダウンロードマネージャー
- iCloudブックマーク同期
- Bookmark export/import
- 広告ブロックON/OFF UI
- 広告ブロック例外設定UI
- ショートカット名設定画面
- AP後の自動reload
- IPv6変更確認
- 多機能なブラウザ設定画面

---

# 17. 設計方針

## 17.1 重視順

1. 動作安定性
2. 軽量さ
3. 操作数の少なさ
4. デバッグ容易性
5. UIの簡潔さ

## 17.2 過剰設計を避ける

一般ブラウザを作るのではなく、必要なWeb閲覧 + 特殊操作を最短で行うアプリとして実装する。

---

# 18. GitHub Actionsビルド

macOS GitHub-hosted runnerでiOSアプリをビルドする。

想定:

1. XcodeGenでproject生成
2. unsigned build
3. `.app`生成
4. `Payload`構造へ配置
5. `.ipa`生成
6. `MiniBrowser.ipa` artifactとして受け渡し

SideStore署名前提。

既存のWindows + GitHub Actions + SideStore環境を壊さないこと。

---

# 19. 共通IPA自動配送基盤

MiniBrowserだけではなく、今後作るiOSアプリでも再利用できる共通仕組みとして構築する。

## 19.1 目的

従来の以下の手作業をなくす。

```text
GitHubサイトを開く
→ Actions
→ Artifactを探す
→ ZIP download
→ 解凍
→ iCloud Driveへコピー
```

理想:

```text
Codex / GitHubへ更新
→ macOS runnerでIPA build
→ build成功
→ Windows self-hosted runner job発火
→ IPA取得
→ iCloud Drive Downloadsへ即時配置
→ iPhoneから利用
```

## 19.2 Windows保存先

固定:

`%MINIBROWSER_DELIVERY_DIRECTORY%`

MiniBrowserの場合:

`%MINIBROWSER_DELIVERY_DIRECTORY%\MiniBrowser.ipa`

更新時は同名ファイルを上書き。

## 19.3 方式

Windows 11 PCをGitHub Actions self-hosted runnerとして登録する。

Runnerは共通用途にする。

macOS build job成功後に、Windows self-hosted runner jobを実行する。

Windows側jobは:

1. macOS jobのIPA artifact取得
2. 必要ならartifact展開
3. IPA単体を抽出
4. 指定iCloud folderへコピー
5. 同名IPAを上書き
6. 終了

## 19.4 軽量性

ゲーム等のPC性能に影響を与えないことを重視。

- iOS buildはWindows側で行わない
- 重い処理はGitHub macOS runner
- Windows runnerは待機 + 小さなartifact download/copyだけ
- 不要な常駐監視アプリを別途作らない
- 定期ポーリングはしない
- GitHub Actionsからjobが来た時だけ処理

self-hosted runner自体の待機時負荷も可能な限り小さくする。

## 19.5 共通化

今後別アプリでも、

- app name
- artifact name
- destination filename

だけ変更すれば同じ仕組みを使えるようにする。

可能なら再利用可能workflowまたは共通script化する。

例:

```text
AppA.ipa
AppB.ipa
MiniBrowser.ipa
```

を同じiCloud Downloadsへ個別ファイル名で配置可能にする。

---

# 20. Codexへの実装指示

以下の順で実装すること。

## Phase 1: 最小ブラウザ

- SwiftUI app
- WKWebView
- URL入力
- 戻る / 進む / 更新
- URL永続化
- 縦画面固定

## Phase 2: UA

- 最大300 UA（根拠が揃った件数まで）
- cyclic切替
- 永続化
- reload
- notification

## Phase 3: Cookie

- 現在domain関連Cookie取得
- 削除
- reload
- 再取得確認
- 結果通知
- logging

## Phase 4: AP + IPv4

- custom URL scheme
- Shortcuts起動
- `セルラー再接続`
- MiniBrowser自動復帰
- IPv4前後比較
- 自動reloadなし

## Phase 5: Bookmark / Bookmarklet

- 一覧
- add/edit/delete/reorder
- long JavaScript editor
- `evaluateJavaScript`
- persistence

## Phase 6: Ad block

- lightweight content blocker
- future exception architecture

## Phase 7: Debug log

- rolling log
- clipboard copy
- secret values excluded

## Phase 8: Build / Delivery

- GitHub Actions macOS build
- unsigned IPA
- Windows self-hosted runner
- iCloud Drive auto copy

---

# 21. 実装完了条件

MVP完了とみなす条件:

1. iPhone実機で起動
2. URL入力からWeb閲覧可能
3. 戻る / 進む / 更新が動作
4. UAカタログを切替可能（最大300種）
5. UA選択状態が再起動後も残る
6. Cookieボタンで現在サイト関連Cookieのみ削除できる
7. LocalStorageがCookie操作で消えない
8. reload後のCookie再取得を判定できる
9. `セルラー再接続` を起動できる
10. Shortcuts後にMiniBrowserへ自動復帰
11. AP後にページを勝手にreloadしない
12. 外向きIPv4前後を比較できる
13. 一時通知がstack表示される
14. 広告ブロックが常時動作
15. Bookmarklet長文を保存・編集・実行できる
16. ブックマーク順序が保存される
17. デバッグログをclipboardへコピーできる
18. 30秒読み込みtimeoutが動作
19. GitHub Actionsでunsigned IPAが生成される
20. build成功後、Windows self-hosted runner経由で
    `%MINIBROWSER_DELIVERY_DIRECTORY%\MiniBrowser.ipa`
    へ自動配置される

---

# 22. Codexの裁量範囲

以下はCodex側で妥当な実装を選んでよい。

- SwiftUI / UIKit bridgeの内部構造
- MVVM等の採否
- persistence方式
- logging実装
- notification queue実装
- Bookmark model
- 具体的なContent Blocker rule構造
- IPv4 endpoint選定
- GitHub Actions YAML内部構造
- reusable workflow化
- self-hosted runner用script構造
- UI spacing / font size / icon選定
- エッジケース処理

ただし、本仕様書で明示されたユーザー操作・保存範囲・自動reload有無・Cookie対象・AP挙動等は変更しない。

---

# 23. 実装時の注意

- Cookie値をログへ出力しない
- Password / token / form内容をログへ出力しない
- WebKitの通常サイトデータをCookieボタンで無差別削除しない
- AP復帰後に自動reloadしない
- UA変更時にCookieを削除しない
- ブックマークレットの長さを勝手に制限しない
- UIボタンを独自判断で増やさない
- 設定画面をMVPに追加しない
- iOS 26未満対応のための複雑なfallbackは不要
- unsigned IPA + SideStore運用を前提とする
- Windows側にXcode build責務を持たせない
