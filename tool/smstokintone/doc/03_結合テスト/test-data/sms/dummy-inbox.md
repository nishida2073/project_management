# 受信箱のダミー SMS

エミュレーター（emulator-5554）の受信箱に入れる、テスト用の SMS の一覧です。

## 一覧

| No | 送信元 | 日時 | 本文 | 入れ方 |
|---|---|---|---|---|
| 1 | 0312345601 | 投入時の時刻 | dummy one line | `adb emu sms send` |
| 2 | 0312345602 | 投入時の時刻 | test-company / test-taro / body-test（3 行） | `adb emu sms send` |
| 3 | 0312345603 | 投入時の時刻 | sample-company / sample-taro / body-b（3 行） | `adb emu sms send` |
| 4 | 0312345604 | 投入時の時刻 | dummy text without company | `adb emu sms send` |
| 5 | 0312345605 | 投入時の時刻 | test-company / test-taro / body-c（3 行） | `adb emu sms send` |
| 6 | 0312345620 | 2027-01-01 00:00（日本時間） | dated test | データベースへ直接追加 |

## 補足

- No 1〜5 は、`adb emu sms send` で入れます。アプリは受信として処理します（会社名の抽出、自動送信、返信）。
- No 6 は、日付を指定するため、SMS のデータベース（`mmssms.db`）へ直接入れます。アプリは受信として処理しません（受信箱の表示だけです）。
- 受信箱は、テストを 1 本実行するたびに空にします（`run-tests.ps1` が、エミュレーターのときに消します）。
- 本文の改行は、`adb emu sms send` の引数に、実際の改行を入れて渡します。
