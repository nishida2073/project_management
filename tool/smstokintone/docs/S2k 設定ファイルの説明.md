# S2k 設定ファイルの説明

## 設定ファイルについて

### 概要
アプリの「設定のインポート・エクスポート」画面で扱うJSONファイルの仕様です。付属の `s2k_settings_template.json`（テンプレート）と対応します。

### 設定ファイルの構成について

設定ファイルは次の3つのブロックからなる1つのJSONです。

```json
{
  "appConfig":          { ... },   // アプリの設定
  "sendTargetConfig":   [ ... ],   // 送信先（kintone接続設定）のリスト
  "senderInfoConfig":   [ ... ]    // 送信元情報（会社名・氏名）のリスト
}
```

- **エクスポート**で生成されるファイルも、この **同じ形式** になります。
- **インポート**時は、ファイルに含まれるブロック **だけ** が反映されます。含まれないブロックは変更されません。送信先（`sendTargetConfig`）は送信先名（`name`）をキーに既存へマージされ、送信元情報（`senderInfoConfig`）はファイルの内容で置き換わります。
- `appConfig` 内の各キーはすべて省略可能で、ファイルに含まれないキーはアプリの既定値で補われます（部分指定可）。なお `appConfig` が空オブジェクト（`{}`）の場合はブロック未指定として扱われ、反映されません。
- JSON にはコメントを書くことができません（`//` や `/* */` を含めるとインポートエラーになります）。このドキュメントの「例・利用できる値」を参考に値を編集してください。

---

## 各ブロックの詳細について

### `appConfig`（アプリの設定）

`appConfig` は、アプリ全体に共通する動作設定をまとめたオブジェクトです。SMS受信時の送信モード（自動／手動）と送信対象、抽出異常・未実施SMSの扱い、自動返信、ログ画面の自動再読み込み、継続SMSの引き継ぎ、テーマ（配色）、SMS検索画面の初期表示、本文からの会社名・氏名の抽出ルールなどをまとめて指定します。

**注意**
- `appConfig` 内のキーはすべて省略可能です。ファイルに含まれないキーはアプリの既定値で補われるため、変更したいキーだけを指定できます（部分指定可）。
- `appConfig` が空オブジェクト（`{}`）の場合はブロック未指定として扱われ、何も反映されません。
- SMS検索画面の「送信先」フィルタの初期値には、既存の送信先IDを指定してください。存在しないIDを指定した場合、フィルタは「すべて」に戻ります。

#### 設定内容

| キー | 意味 | 利用できる値 | 例 |
| --- | --- | --- | --- |
| `sendEnabled` | 自動送信モードか手動送信モードか | `true` / `false` | `true` |
| `sendExtractionFailedEnabled` | 自動送信時、会社名・氏名を抽出できなかったSMSも送信するか | `true` / `false` | `false` |
| `sendExtractionNotPerformedEnabled` | 自動送信時、抽出状況が未実施（継続SMS）のSMSも送信するか | `true` / `false` | `true` |
| `searchExtractionFailedEnabled` | SMS検索画面で抽出異常のSMSを選択可能にするか | `true` / `false` | `false` |
| `searchExtractionNotPerformedEnabled` | SMS検索画面で抽出未実施（継続SMS）のSMSを選択可能にするか | `true` / `false` | `true` |
| `autoReplyExtractionFailedEnabled` | 自動受信時、抽出異常のSMSへ自動返信するか | `true` / `false` | `false` |
| `autoReplyCooldownSeconds` | 同一送信元への自動返信を再送信するまでの間隔 | 整数（秒） | `10` |
| `autoRefreshEnabled` | ログ画面（送信履歴）を自動再読み込みするか | `true` / `false` | `true` |
| `autoRefreshIntervalSeconds` | 自動再読み込みの間隔 | 整数（秒） | `5` |
| `smsMatchToleranceSeconds` | 自動受信SMSのログと端末上のSMSを突き合わせる許容範囲 | 整数（秒） | `15` |
| `bodyExcerptLength` | ログ一覧に表示する本文抜粋の文字数 | 整数 | `100` |
| `continuationEnabled` | 継続SMSの引き継ぎ機能を有効にするか | `true` / `false` | `true` |
| `continuationScope` | 引き継ぎをどこまで遡るか | `UNLIMITED`（過去に一度でも抽出正常なら常に引き継ぎ）／ `SAME_DAY`（同暦日のみ） | `UNLIMITED` |
| `continuationShowUserNameEnabled` | 継続SMSについて送信元電話番号の代わりに引き継いだ氏名を表示するか | `true` / `false` | `true` |
| `themeMode` | アプリの配色モード | `LIGHT` / `DARK` | `LIGHT` |
| `smsSearchDateRangeDays` | SMS検索画面を開いた際の受信日の範囲 | 整数（日） | `1` |
| `searchFiltersVisibleByDefault` | SMS検索画面を開いた際に検索条件エリアを表示した状態にするか | `true` / `false` | `true` |
| `smsExtractionSuccessReplyBody` | SMS検索画面で長押しした際に開く返信画面へ自動入力する文言 | 文字列 | `"NTTデータユニバーシティ\n運営事務局です。\n"` |
| `smsExtractionFailedReplyBody` | 抽出失敗のSMSへの返信時に使う文言 | 文字列 | `"…（記入例）…\nここに内容を入力"` |
| `defaultSendTargetFilterId` | SMS検索画面の「送信先」フィルタの初期値 | 送信先ID／ `null`（すべて）／ `"__filter_key_unset__"`（未設定） | `null` |
| `aiExtractionEnabled` | 本文の会社名・氏名の抽出に、ルールベースの代わりに端末上のAI（ML Kit GenAI / Gemini Nano）を使うか。非対応端末では自動的にルールベースへ | `true` / `false` | `false` |
| `companyNameExtractionEnabled` | 本文から会社名・氏名を抽出するか。`false` の場合は抽出せず全送信先へ送る | `true` / `false` | `true` |
| `companyNameAutoConversionEnabled` | 抽出した会社名に、英数字を半角大文字・それ以外を全角へ統一する変換を適用するか | `true` / `false` | `false` |
| `companyNameFixedConversions` | 会社名の固定変換ルールの配列。先頭から順に `from` を `to` へ置換 | 変換ルールの配列／ `[]` | `[{"from": "ユニバ", "to": "ユニバーシティ"}]` |
| `defaultSendNoneOnlyEnabled` | SMS検索画面を開いた際の「送信」の「未」チェックを初期ONにするか | `true` / `false` | `false` |
| `defaultExtractionFailedOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「異常」チェックを初期ONにするか | `true` / `false` | `false` |
| `defaultExtractionSucceededOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「正常」チェックを初期ONにするか | `true` / `false` | `false` |
| `defaultExtractionNotPerformedOnlyEnabled` | SMS検索画面を開いた際の「抽出状況」の「未実施」チェックを初期ONにするか | `true` / `false` | `false` |
| `defaultSentAutoOnlyEnabled` | SMS検索画面を開いた際の「送信」の「済（自動）」チェックを初期ONにするか | `true` / `false` | `false` |
| `defaultSentManualOnlyEnabled` | SMS検索画面を開いた際の「送信」の「済（手動）」チェックを初期ONにするか | `true` / `false` | `false` |

---

### `sendTargetConfig`（送信先の設定）

`sendTargetConfig` は送信先（kintone接続設定）のリストです。kintoneの接続先（サブドメイン・アプリID・認証情報）、レコードへの書き込みフィールド、既存レコードへの追記の判定、本文から抽出した会社名での振り分け条件などを送信先ごとにまとめて指定します。振り分け条件のいずれかが会社名に含まれればその送信先へ振り分けられ、**振り分け条件が空の送信先は、どの送信先にも一致しなかったときのフォールバック（デフォルト）送信先**になります。テンプレートの `sendTargetConfig` は記入例（プレースホルダー）です。

**注意**
インポート時は送信先名をキーに既存の送信先へマージされます。既存と同じ送信先名の送信先があればその内容が上書きされ（送信先IDは既存のまま維持）、なければ新規追加されます。ファイルに含まれない既存の送信先は変更されません。なお送信先IDは省略でき、省略時は自動生成されます。

#### 設定内容

| キー | 意味 | 利用できる値 | 例 |
| --- | --- | --- | --- |
| `id` | 送信先を一意に識別するID（UUID）。省略可 | UUID文字列 | `"00000000-0000-0000-0000-000000000000"` |
| `name` | 送信先の表示名 | 文字列 | `"本社"` |
| `companyName` | この送信先の会社名（本文抽出が無効な送信先判定で使われる） | 文字列 | `"NTTデータユニバーシティ"` |
| `keywords` | 振り分け条件のキーワード配列。いずれかが会社名に含まれればこの送信先へ。**空配列＝フォールバック送信先** | 文字列の配列 | `["NTTデータ", "ユニバーシティ"]` |
| `subdomain` | kintoneのサブドメイン（`https://{subdomain}.cybozu.com` のホスト名部分） | 文字列 | `"univ-kyousai-{X}"` |
| `appId` | kintoneアプリのID | 文字列 | `"1"` |
| `authMethod` | kintoneへの接続認証方式 | `PASSWORD` / `API_TOKEN` | `PASSWORD` |
| `apiToken` | APIトークン認証（`API_TOKEN`）時の値。パスワード認証時は未使用 | 文字列 | `""` |
| `loginName` | パスワード認証（`PASSWORD`）時のログイン名。APIトークン認証時は未使用 | 文字列 | `"kintoneのログイン名"` |
| `loginPassword` | パスワード認証（`PASSWORD`）時のパスワード。APIトークン認証時は未使用 | 文字列 | `"kintoneのパスワード"` |
| `fieldSender` | 送信元電話番号を書き込むkintoneフィールドのフィールドコード | 文字列 | `"sender"` |
| `fieldHistory` | 本文（複数SMSを連結する場合は履歴として蓄積）を書き込むフィールドコード | 文字列 | `"history"` |
| `fieldDatetime` | 最終受信日時を書き込む・既存レコード検索にも使うフィールドコード | 文字列 | `"receive_datetime"` |
| `fieldType` | 登録種別を書き込む・既存レコード検索の絞り込みにも使うフィールドコード | 文字列 | `"registration_type"` |
| `updateToleranceHours` | 同一送信元の既存レコードへ追記するか判定する許容時間。`updateToleranceMode` が `HOURS` のときのみ使う | 整数（時間） | `5` |
| `updateToleranceMode` | 既存レコードへ追記するか新規登録するかの判定条件 | `SAME_DATE`（端末の暦日が同じ）／ `HOURS`（許容時間以内） | `SAME_DATE` |
| `fieldCompanyName` | 抽出した会社名を書き込むフィールドコード。空なら書き込まない | 文字列 | `"company_name"` |
| `fieldUserName` | 抽出した氏名を書き込むフィールドコード。空なら書き込まない | 文字列 | `"user_name"` |
| `fieldBody` | SMS本文全体（原文）を書き込むフィールドコード。空なら書き込まない | 文字列 | `"body"` |


---

### `senderInfoConfig`（送信元情報）

`senderInfoConfig` は送信元ごとの、最新かつ抽出状況が正常なSMSから引き継いだ会社名・氏名などのリストです。送信元を識別するキー、引き継ぐ会社名・氏名、そのSMSの受信日時、編集画面での表示用の元アドレスなどをまとめて指定します。テンプレートの `senderInfoConfig` は記入例（プレースホルダー）です。

**注意**
インポート時はこのリストで送信元情報が置き換わります。各要素では送信元を識別するキーまたは元の送信元アドレス（電話番号など）のどちらかが必須で、両方ない場合はインポートエラーになります。送信元キーは電話番号を末尾8桁へ正規化した値で、省略時は元の送信元アドレスから自動生成されます。


#### 設定内容

| キー | 意味 | 例・利用できる値 |
| --- | --- | --- |
| `senderKey` | 正規化済みの送信元キー。電話番号は末尾8桁になります（例: `09012345678` → `012345678`）。省略時は `senderAddress` から自動生成 | `"012345678"` |
| `companyName` | 引き継ぐ会社名 | `"NTTデータユニバーシティ"` |
| `userName` | 引き継ぐ氏名 | `"ユニバ太郎"` |
| `timestampMillis` | そのSMSの受信日時（Unixエポックミリ秒）。省略時は取り込み時点の日時を使う | `0`（初期例）／ `"1726704000000"` など |
| `senderAddress` | 正規化前の元の送信元アドレス（電話番号など）。編集画面での表示用 | `"09012345678"` |

---

## 設定ファイルのサンプル

以下は、設定ファイルの全体像を示す1つのサンプル（記入例）です。`s2k_settings_template.json`（テンプレート）と同じ形式です。

インポート時は、このサンプルのように「変更したい内容だけ」をファイルへ書いて使用します。以下では `appConfig` の一部キーだけを指定し、`sendTargetConfig`・`senderInfoConfig` には記入例を入れています。

```json
{
  "appConfig": {
    "sendEnabled": true,
    "sendExtractionFailedEnabled": false,
    "sendExtractionNotPerformedEnabled": true,
    "autoReplyExtractionFailedEnabled": false,
    "autoReplyCooldownSeconds": 10,
    "autoRefreshEnabled": true,
    "autoRefreshIntervalSeconds": 5,
    "continuationEnabled": true,
    "continuationScope": "UNLIMITED",
    "themeMode": "LIGHT",
    "smsSearchDateRangeDays": 1,
    "searchFiltersVisibleByDefault": true,
    "smsExtractionSuccessReplyBody": "NTTデータユニバーシティ\n運営事務局です。\n",
    "smsExtractionFailedReplyBody": "…（記入例）…\nここに内容を入力",
    "defaultSendTargetFilterId": null,
    "aiExtractionEnabled": false,
    "companyNameExtractionEnabled": true,
    "companyNameAutoConversionEnabled": false,
    "companyNameFixedConversions": [],
    "defaultSendNoneOnlyEnabled": false,
    "defaultExtractionFailedOnlyEnabled": false,
    "defaultExtractionSucceededOnlyEnabled": false,
    "defaultExtractionNotPerformedOnlyEnabled": false,
    "defaultSentAutoOnlyEnabled": false,
    "defaultSentManualOnlyEnabled": false
  },
  "sendTargetConfig": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "name": "（例）本社",
      "companyName": "NTTデータユニバーシティ",
      "keywords": [
        "NTTデータ",
        "ユニバーシティ"
      ],
      "subdomain": "univ-kyousai-{X}",
      "appId": "1",
      "authMethod": "PASSWORD",
      "apiToken": "",
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
  "senderInfoConfig": [
    {
      "senderKey": "012345678",
      "companyName": "（例）NTTデータユニバーシティ",
      "userName": "（例）ユニバ太郎",
      "timestampMillis": 0,
      "senderAddress": "09012345678"
    }
  ]
}
```

- キー名は上の各ブロックの表（`appConfig`・`sendTargetConfig`・`senderInfoConfig`）を参照してください。
- `appConfig` は部分指定ができるため、変更したいキーだけを書いても構いません。このサンプルは記入例（プレースホルダー）です。
