# ルールの再作成

## 概要

`計画算定シート`の条件付き書式ルールを全部クリアし、意図した2つのルールだけに作り直すツールです。

条件付き書式のルールが増殖し、Excelが重くなる・固まる、という問題への対処用です。

## 構成

- `rebuild-conditional-formatting.bat` — 実行用のラッパー（ドラッグ＆ドロップ対応）
- `rebuild-conditional-formatting.ps1` — 実際の処理を行うPowerShellスクリプト
- `backup/` — 実行のたびに作られる、対象`.xlsm`のバックアップを置くサブフォルダ（自動で作成されます）
- `logs/` — 実行結果を日付ごとに記録するサブフォルダ（自動で作成されます）

## 基本的な使い方

### 実行方法

```bat
rebuild-conditional-formatting.bat
```

ダブルクリックでの実行のほか、**Excelファイル（`.xlsm`）をこの`.bat`にドラッグ＆ドロップ**して実行することもできます。

- 引数なし（ダブルクリック）で実行した場合：1つ上のフォルダにある`原価管理シート.xlsm`が対象になります
- ファイルをドラッグ＆ドロップした場合：そのドロップしたファイルが対象になります

`.bat`は既定値のまま`.ps1`を呼び出すだけなので、対象ファイル（`-XlsmPath`）以外を変えたい場合は`.ps1`を直接呼び出します。

```powershell
.\rebuild-conditional-formatting.ps1 -XlsmPath "C:\path\to\別の原価管理シート.xlsm" -SheetName "計画算定シート" -Rules @(
    @{ Range = "D5:AG5000"; Formula = '=$Q5="売上"'; Color = "#DDEBF7" },
    @{ Range = "D5:AG5000"; Formula = '=$S5="実績"'; Color = "#FCE4D6" }
)
```

- `-XlsmPath`：対象の`.xlsm`ファイルへの直接パス
- `-SheetName`：対象のシート名（既定値：`計画算定シート`）
- `-Rules`：作成するルールの配列。各要素は`@{ Range = ...; Formula = ...; Color = ... }`の形のハッシュテーブルで、要素数はいくつでも追加可能（既定値は現在の2ルール）
  - `Range`：ルールを設定する範囲（例：`"D5:AG5000"`）
  - `Formula`：条件付き書式の数式（例：`'=$Q5="売上"'`）
  - `Color`：背景色。`#RRGGBB`形式のHex文字列（Excelの「その他の色」ダイアログの「Hex」欄に表示される値をそのまま使えます）
- `-BackupDir`：バックアップの出力先フォルダ。既定では自分のフォルダ内の`backup`サブフォルダ
- `-LogDir`：実行ログの出力先フォルダ。既定では自分のフォルダ内の`logs`サブフォルダ
