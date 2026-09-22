# インポート・エクスポート用の設定ファイル

## 設定ファイルについて

### 概要
　アプリの「設定のインポート・エクスポート」画面で扱うJSONファイルの仕様です。

### 設定ファイルの構成について
　設定ファイルは次の3つのブロックからなる1つのJSONです。

```json
{
  "appConfig":             { ... },   // アプリの設定
  "sendTargetConfig":      [ ... ],   // 送信先の一覧
  "continuationInfoConfig": [ ... ]    // 引継ぎ内容の一覧
}
```

　**エクスポート**で生成されるファイルも、この **同じ形式** になります。<br>
　**インポート**時は、ファイルに含まれるブロック **だけ** が反映されます。<br>
　ブロックごとの反映方法の詳細は、下記を参照してください。

---

## 各ブロックの詳細について

### `appConfig`（アプリの設定）
　`appConfig` は、アプリの動作設定をまとめたものです。<br>
　SMS受信時の送信モード（自動／手動）と送信対象、抽出異常・引継ぎSMSの扱い、自動返信、ログ画面の自動再読み込み、継続SMSの引継ぎ、テーマ（配色）、SMS検索画面の初期表示、本文からの会社名・氏名の抽出ルールなどをまとめて指定します。

> **注意**
> - `appConfig` 内のキーはすべて省略可能です。ファイルに含まれないキーはアプリの既定値で補われるため、変更したいキーだけを指定できます（部分指定可）。
> - `appConfig` が空（`{}`）の場合はブロック未指定として扱われ、何も反映されません。
> - SMS検索画面の「送信先」フィルタの初期値には、既存の送信先名を指定してください。存在しない送信先名を指定した場合、フィルタは「すべて」に戻ります。

#### 設定内容

| キー | 意味 | 利用できる値 |
| --- | --- | --- |
| `themeMode` | アプリの配色モード | `LIGHT` / `DARK`<br><br>例）`LIGHT` |
| `sendEnabled` | 自動送信モードか手動送信モードか | `true` / `false`<br><br>例）`true` |
| `sendExtractionFailedEnabled` | 自動送信時、抽出失敗のSMS（会社名・氏名を抽出できなかったSMS）も送信するか | `true` / `false`<br><br>例）`true` |
| `sendExtractionContinuationEnabled` | 自動送信時、抽出引継ぎ（継続SMS）のSMSも送信するか | `true` / `false`<br><br>例）`true` |
| `replyEnabled` | 自動受信時、抽出失敗のSMSに対して自動返信するか | `true` / `false`<br><br>例）`false` |
| `replyCooldownSeconds` | 同一送信元への自動返信を再送信するまでの間隔 | 整数（秒）<br><br>例）`10` |
| `replySuccessBody` | SMS検索画面で長押しした際に開く返信画面へ自動入力する文言 | 文字列<br><br>例）`"NTTデータユニバーシティ\n運営事務局です。\n"` |
| `replyFailedBody` | 抽出失敗のSMSへの返信時に使う文言 | 文字列<br><br>例）`"…（記入例）…\nここに内容を入力"` |
| `searchDateRangeDays` | SMS検索画面を開いた際の受信日の範囲 | 整数（日）<br><br>例）`1` |
| `searchFiltersVisibleByDefault` | SMS検索画面を開いた際に検索条件エリアを表示した状態にするか | `true` / `false`<br><br>例）`true` |
| `searchSendTargetFilterName` | SMS検索画面の「送信先」フィルタの初期値 | 送信先名（例）`"本社"`）：その送信先を初期選択<br>`null`：すべて<br>`"__filter_key_unset__"`：なし（どの送信先にも一致しないSMSのみ）<br><br>例）`null` |
| `searchExtractionFailedEnabled` | SMS検索画面で、抽出失敗のSMSを選択可能にするか | `true` / `false`<br><br>例）`true` |
| `searchExtractionContinuationEnabled` | SMS検索画面で、抽出引継ぎ（継続SMS）のSMSを選択可能にするか | `true` / `false`<br><br>例）`true` |
| `searchSendNoneOnlyEnabled` | SMS検索画面を開いた際の「送信」の「未」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `searchExtractionFailedOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「異常」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `searchExtractionSucceededOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「正常」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `searchExtractionContinuationOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「引継ぎ」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `searchSentAutoOnlyEnabled` | SMS検索画面を開いた際の「送信」の「済（自動）」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `searchSentManualOnlyEnabled` | SMS検索画面を開いた際の「送信」の「済（手動）」チェックを初期ONにするか | `true` / `false`<br><br>例）`false` |
| `extractionAiEnabled` | 本文からの会社名・氏名の抽出に端末上のAI（ML Kit GenAI / Gemini Nano）を使うか。非対応端末は自動フォールバック | `true` / `false`<br><br>例）`false` |
| `extractionCompanyNameEnabled` | 本文からの会社名・氏名の抽出機能全体の有効/無効 | `true` / `false`<br><br>例）`true` |
| `extractionCompanyNameAutoConversionEnabled` | 抽出結果の会社名に、英数字は半角大文字・それ以外は全角に統一する変換を適用するか | `true` / `false`<br><br>例）`false` |
| `extractionCompanyNameFixedConversions` | 抽出結果の会社名に適用する固定変換ルール。先頭から順に `from` を `to` へ置換 | 変換ルールの配列／ `[]`<br><br>例）`[{"from": "ユニバ", "to": "ユニバーシティ"}]` |
| `continuationEnabled` | 継続SMSの引継ぎ機能全体の有効/無効 | `true` / `false`<br><br>例）`true` |
| `continuationScope` | 継続SMSの引継ぎを送信元ごとにどこまで遡るか | `UNLIMITED`（過去に一度でも抽出正常なら常に引継ぎ）／ `SAME_DAY`（同暦日のみ）<br><br>例）`UNLIMITED` |
| `continuationShowUserNameEnabled` | SMS検索画面・ログ画面で、継続SMSの場合は送信元電話番号の代わりに引き継いだ氏名を表示するか | `true` / `false`<br><br>例）`true` |
| `logRefreshEnabled` | SMS送信履歴画面を自動再読み込みするか | `true` / `false`<br><br>例）`true` |
| `logRefreshIntervalSeconds` | 自動再読み込み間隔 | 整数（秒）<br><br>例）`5` |
| `logMatchToleranceSeconds` | 自動受信SMSのログと端末上のSMSを突き合わせる際の許容範囲 | 整数（秒）<br><br>例）`15` |
| `logBodyExcerptLength` | ログ一覧に表示する本文抜粋の文字数 | 整数<br><br>例）`100` |

---

### `sendTargetConfig`（送信先の設定）
　`sendTargetConfig` は送信先の設定をまとめたものです。<br>
　送信先やkintoneの接続先などを送信先ごとにまとめて指定します。<br>

> **注意**
> - インポート時は送信先名をキーに既存の送信先へマージされます。
> - 既存と同じ送信先名の送信先があればその内容が上書きされ、なければ新規追加されます。
> - ファイルに含まれない既存の送信先は変更されません。
> - 1つのファイル内で送信先名が重複している場合はインポートエラーになります。

#### 設定内容

| キー | 意味 | 利用できる値 |
| --- | --- | --- |
| `name` | 送信先の表示名 | 文字列<br><br>例）`"本社"` |
| `companyName` | この送信先の会社名 | 文字列<br><br>例）`"NTTデータユニバーシティ"` |
| `keywords` | 振り分け条件のキーワード配列。<br>**空配列の場合:デフォルトの送信先** | 文字列の配列<br><br>例）`["NTTデータ", "ユニバーシティ"]` |
| `subdomain` | kintoneのサブドメイン | 文字列<br><br>例）`"univ-kyousai-{X}"` |
| `appId` | kintoneアプリのID | 文字列<br><br>例）`"1"` |
| `loginName` | パスワード認証（kintoneのログイン名とパスワード）でkintoneへ接続する際のログイン名 | 文字列<br><br>例）`"kintoneのログイン名"` |
| `loginPassword` | パスワード認証で使うkintoneのパスワード | 文字列<br><br>例）`"kintoneのパスワード"` |
| `fieldSender` | 送信元電話番号を書き込むkintoneフィールドのフィールドコード | 文字列<br><br>例）`"sender"` |
| `fieldHistory` | 本文（複数SMSを連結する場合は履歴として蓄積）を書き込むフィールドコード | 文字列<br><br>例）`"history"` |
| `fieldDatetime` | 最終受信日時を書き込む・既存レコード検索にも使うフィールドコード | 文字列<br><br>例）`"receive_datetime"` |
| `fieldType` | 登録種別を書き込む・既存レコード検索の絞り込みにも使うフィールドコード | 文字列<br><br>例）`"registration_type"` |
| `updateToleranceHours` | 同一送信元の既存レコードへ追記するか判定する許容時間。`updateToleranceMode` が `HOURS` のときのみ使う | 整数（時間）<br><br>例）`5` |
| `updateToleranceMode` | 既存レコードへ追記するか新規登録するかの判定条件 | `SAME_DATE`（端末の暦日が同じ）／ `HOURS`（許容時間以内）<br><br>例）`SAME_DATE` |
| `fieldCompanyName` | 抽出した会社名を書き込むフィールドコード。空なら書き込まない | 文字列<br><br>例）`"company_name"` |
| `fieldUserName` | 抽出した氏名を書き込むフィールドコード。空なら書き込まない | 文字列<br><br>例）`"user_name"` |
| `fieldBody` | SMS本文全体（原文）を書き込むフィールドコード。空なら書き込まない | 文字列<br><br>例）`"body"` |


---

### `continuationInfoConfig`（引継ぎ内容）
　`continuationInfoConfig` は引継ぎ内容（過去の SMS から引き継いだ会社名・氏名情報）の設定をまとめたものです。

> **注意**
> - インポート時はこの一覧で送信元情報が置き換わります。
> - 各要素では `senderAddress`（元の送信元アドレス）が必須です。ない場合はインポートエラーになります。

#### 設定内容

| キー | 意味 | 利用できる値 |
| --- | --- | --- |
| `senderAddress` | 元の送信元アドレス（電話番号など）。送信元キーの自動生成と編集画面での表示に使う | 文字列<br><br>例）`"09012345678"` |
| `companyName` | 引き継ぐ会社名 | 文字列<br><br>例）`"NTTデータユニバーシティ"` |
| `userName` | 引き継ぐ氏名 | 文字列<br><br>例）`"ユニバ太郎"` |
| `timestampMillis` | そのSMSの受信日時（Unixエポックミリ秒）。省略時は取り込み時点の日時を使う | 整数（Unixエポックミリ秒）<br><br>例）`0`（初期例）／ `1726704000000` |

---

## 設定ファイルのサンプル
　以下は、設定ファイルの全体像を示す1つのサンプル（記入例）です。<br>
　インポート時は、このサンプルのように「変更したい内容だけ」をファイルへ書いて使用します。<br>

　以下は `appConfig` の一部キーだけを指定し、`sendTargetConfig`・`continuationInfoConfig` には記入例を入れています。

```json
{
  "appConfig": {
    "themeMode": "LIGHT",
    "sendEnabled": true,
    "sendExtractionFailedEnabled": true,
    "sendExtractionContinuationEnabled": true,
    "replyEnabled": false,
    "replyCooldownSeconds": 10,
    "replySuccessBody": "NTTデータユニバーシティ\n運営事務局です。\n",
    "replyFailedBody": "…（記入例）…\nここに内容を入力",
    "searchDateRangeDays": 1,
    "searchFiltersVisibleByDefault": true,
    "searchSendTargetFilterName": null,
    "searchExtractionFailedEnabled": true,
    "searchExtractionContinuationEnabled": true,
    "searchSendNoneOnlyEnabled": false,
    "searchExtractionFailedOnlyEnabled": false,
    "searchExtractionSucceededOnlyEnabled": false,
    "searchExtractionContinuationOnlyEnabled": false,
    "searchSentAutoOnlyEnabled": false,
    "searchSentManualOnlyEnabled": false,
    "extractionAiEnabled": false,
    "extractionCompanyNameEnabled": true,
    "extractionCompanyNameAutoConversionEnabled": true,
    "extractionCompanyNameFixedConversions": [],
    "continuationEnabled": true,
    "continuationScope": "UNLIMITED",
    "continuationShowUserNameEnabled": true,
    "logRefreshEnabled": true,
    "logRefreshIntervalSeconds": 5,
    "logMatchToleranceSeconds": 15,
    "logBodyExcerptLength": 100
  },
  "sendTargetConfig": [
    {
      "name": "（例）本社",
      "companyName": "NTTデータユニバーシティ",
      "keywords": [
        "NTTデータ",
        "ユニバーシティ"
      ],
      "subdomain": "univ-kyousai-{X}",
      "appId": "1",
      "loginName": "kintoneのログイン名",
      "loginPassword": "kintoneのパスワード",
      "fieldSender": "sender",
      "fieldHistory": "history",
      "fieldDatetime": "receive_datetime",
      "fieldType": "registration_type",
      "updateToleranceHours": 5,
      "updateToleranceMode": "SAME_DATE",
      "fieldCompanyName": "company_name",
      "fieldUserName": "user_name",
      "fieldBody": "body"
    }
  ],
  "continuationInfoConfig": [
    {
      "senderAddress": "09012345678",
      "companyName": "（例）NTTデータユニバーシティ",
      "userName": "（例）ユニバ太郎",
      "timestampMillis": 0
    }
  ]
}
```

- キー名は上の各ブロックの表（`appConfig`・`sendTargetConfig`・`continuationInfoConfig`）を参照してください。
- `appConfig` は部分指定ができるため、変更したいキーだけを書いても構いません。このサンプルは記入例です。

---

## 推奨設定ファイル

　異なるイベント開催形態向けの推奨設定ファイルを用意しています。運用方法に応じてアプリへインポートしてご活用ください。

| 形態 | ファイル名 | 概要 |
| --- | --- | --- |
| 単一企業のイベント | `s2k-recommend-個社.json` | 会社名の自動抽出を有効化し、継続SMSは過去に一度でも成功したら引き継ぐ設定です |
| グループ企業の合同開催 | `s2k-recommend-グループ共催.json` | 会社名の自動抽出を有効化し、継続SMSは過去に一度でも成功したら引き継ぐ設定です |
| 地域企業の合同開催 | `s2k-recommend-地域共催.json` | 会社名の自動抽出を有効化し、継続SMSは過去に一度でも成功したら引き継ぐ設定です |
| 金融企業の合同開催 | `s2k-recommend-金融共催.json` | 会社名の自動抽出を有効化し、継続SMSは過去に一度でも成功したら引き継ぐ設定です |
