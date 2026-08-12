# kintoneリソース生成ツール

## 概要

### 実施手順

0. スペーステンプレートから新しいスペースを作成（[0. スペース作成について](#0-スペース作成について)。既存のスペースを使う場合は不要）
1. 対象スペースの現在の状態をダウンロード（[1. ダウンロードについて](#1-ダウンロードについて)）
2. テンプレートとダウンロード結果から設定ファイルを生成し、内容を確認・編集（[2. 設定ファイルの生成について](#2-設定ファイルの生成について)）
3. 設定ファイルの内容をkintoneに反映（[3. kintoneへ反映について](#3-kintoneへ反映について)）
4. 反映結果をkintoneの現在の状態と比較してチェック（[4. データチェックについて](#4-データチェックについて)）

各段階はそれぞれ独立した`.bat`（後述）で、まとめて実行する`.bat`は無い。0→4を続けて実行したい場合は[GUI版](#gui版)の「まとめて実行」（または「一括実行」）を使う。

## ツールの構成

| ファイル/フォルダ | 役割 |
|---|---|
| `create-space-from-template.bat` | 「0. スペース作成」のエントリーポイント |
| `download-kintone-resources.bat` | 「1. ダウンロード」のエントリーポイント |
| `generate-config-from-template.bat` | 「2. 設定ファイルの生成」のエントリーポイント |
| `apply-kintone-resources.bat` | 「3. kintoneへ反映」のエントリーポイント |
| `check-kintone-resources.bat` | 「4. データチェック」のエントリーポイント |
| `scripts\common.ps1` | 5つの`.ps1`が共通で使う関数（kintone REST APIの呼び出し、Excelの読み書き、ログ出力など）。各`.ps1`の先頭でドットソースして読み込まれる。ユーザーが直接実行するものではない |
| `scripts\create-space-from-template.ps1` / `download-kintone-resources.ps1` / `generate-config-from-template.ps1` / `apply-kintone-resources.ps1` / `check-kintone-resources.ps1` | 各段階の実装本体（`.bat`から呼び出される。ユーザーが直接実行するものではない） |
| `template\*.xlsx` | 設定テンプレート（スペース・アプリ名だけで紐づく、共通のメンバー・ACL設定）。書き方は[設定ファイル・テンプレートの構成](#設定ファイルテンプレートの構成)を参照 |
| `download\<スペース識別名>_download.xlsx` | 「1. ダウンロード」の出力＝「2. 設定ファイルの生成」の入力の一つ |
| `config\<スペース識別名>_config.xlsx` | 「2. 設定ファイルの生成」の出力＝「3. kintoneへ反映」「4. データチェック」の入力 |
| `checked\<スペース識別名>_check.xlsx` | 「4. データチェック」の出力 |
| `run-list\*.xlsx` | GUI版「一括実行」タブで読み込む実行一覧ファイル（列は[一括実行](#一括実行)を参照） |
| `build-gui.bat` | GUI版（`kintoneリソース生成ツール.exe`）をビルドするエントリーポイント。[GUI版](#gui版)を参照 |
| `scripts\gui.ps1` / `build-gui.ps1` | GUI版の画面本体、およびそれをexe化するビルドスクリプト（`build-gui.bat`から呼び出される。ユーザーが直接実行するものではない） |
| `clients\set-env.bat` | ローカルのフォルダパス（`COMMON_*`）の既定値をまとめて設定する（他の`.bat`から`call clients\set-env.bat`される） |
| `clients\set-kintone.bat` | kintoneの接続情報（サイトURL・ログイン名・パスワード） |

環境変数はローカルのフォルダパス（`COMMON_*`）が`clients\set-env.bat`、kintoneの接続情報（`KINTONE_*`）が`clients\set-kintone.bat`にまとめてある。書き方は[clients\README.md](clients/README.md)を参照。

## kintoneへのログイン

各`.ps1`は`KINTONE_BASE_URL`（接続先のkintoneサイトURL）に対してREST APIを直接呼び出す（Basic認証）。`KINTONE_LOGIN`/`KINTONE_PASSWORD`が環境変数として設定されていればそれを使い、されていなければ実行時（最初にAPIを呼ぶ直前）にコンソールでログイン名・パスワードの入力を求められる。この3変数はローカルの`clients\set-kintone.bat`にまとめてある（書き方は[clients\README.md](clients/README.md)を参照）。

「0. スペース作成」で使うスペーステンプレートからのスペース作成APIは、スペース管理者（`members`）を1名以上指定しないとエラーになる。このツールはログインに使ったユーザー自身を唯一の管理者として自動的に設定する。

## 処理の詳細

### 環境変数

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `COMMON_DOWNLOAD_PATH` | 「1. ダウンロード」の出力先フォルダ | `download`フォルダ |
| `COMMON_CONFIG_PATH` | 設定ファイル（`*_config.xlsx`）のフォルダ | `config`フォルダ |
| `COMMON_TEMPLATE_PATH` | 設定テンプレート（`template\*.xlsx`）のフォルダ | `template`フォルダ |
| `COMMON_CHECK_OUTPUT_PATH` | 「4. データチェック」の出力先フォルダ | `checked`フォルダ |
| `COMMON_LOG_PATH` | 各段階のログの出力先フォルダ | `log`フォルダ |

### 0. スペース作成について

kintoneの「スペーステンプレート」機能を使って、指定したテンプレートIDから新しいスペースを作成する。元スペースを「テンプレートとして保存」する操作自体はAPIには無いため、kintoneの管理画面で事前に済ませておく必要がある（テンプレートIDはその管理画面のURLから確認できる）。既存のスペースを使う場合はこの段階は不要。

#### 処理の流れ

1. `create-space-from-template.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `create-space-from-template.ps1` が実行される
   1. kintoneにログインする（未設定時はコンソールでログイン名・パスワードを入力）
   2. スペーステンプレートAPIで新しいスペースを作成する（管理者はログインユーザー自身）
   3. 作成されたスペースIDをコンソールとログに出力する
   4. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 引数

| 引数 | 説明 |
|---|---|
| `-TemplateId` | 元にするスペーステンプレートのID |
| `-SpaceName` | 作成するスペースの名前 |

```bat
create-space-from-template.bat -TemplateId 12 -SpaceName "L20 クラススペース"
```

指定しなかった引数は実行時にコンソールで入力を求められる。

#### 出力結果

作成されたスペースIDは`作成されたスペースID: <ID>`としてコンソールとログに出力されるのみで、ファイルへの出力は無い（GUI版では、この行を読み取って次段階の「スペースID」欄に自動入力する）。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `createspace_<スペース名>_yyyyMMdd_HHmmss.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ |

### 1. ダウンロードについて

指定したスペースIDの現在の状態を、`download\<スペース識別名>_download.xlsx`の5シート（`space-settings` / `space-member-list` / `space-app-list` / `space-app-acl` / `space-app-record-acl`）に書き出す。各シートは実行するたびに完全に上書きされる。

#### 処理の流れ

1. `download-kintone-resources.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `download-kintone-resources.ps1` が実行される
   1. kintoneにログインする
   2. 対象スペース（`-SpaceId`）の設定・メンバー・アプリ一覧・アプリACL・レコードACLを取得する
   3. 取得結果を`download\<スペース識別名>_download.xlsx`の5シートに書き出す（既存内容は上書き）
   4. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 引数

| 引数 | 説明 |
|---|---|
| `-SpaceId` | ダウンロード対象のスペースID |
| `-ConfigName` | 出力ファイル名（`download\<CONFIG_NAME>_download.xlsx`の`<CONFIG_NAME>`）に使うスペース識別名 |

```bat
download-kintone-resources.bat -SpaceId 123 -ConfigName L20
```

指定しなかった引数は実行時にコンソールで入力を求められる。

#### 出力結果

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<スペース識別名>_download.xlsx` | ダウンロード先（`COMMON_DOWNLOAD_PATH`） | 対象スペースの現在の状態（5シート構成、[設定ファイル・テンプレートの構成](#設定ファイルテンプレートの構成)を参照） |
| `download_<スペース識別名>_yyyyMMdd_HHmmss.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ |

#### 注意点

> アプリのACL・レコードACLの取得に失敗したアプリがあっても処理全体は中断せず、そのアプリはログに警告として記録した上で続行する（該当アプリの`space-app-acl`/`space-app-record-acl`は空のまま出力される）。

### 2. 設定ファイルの生成について

テンプレート（`template\<設定テンプレート名>.xlsx`、スペースID・アプリIDを持たずアプリ名だけで紐づく共通のメンバー・ACL設定）と、ダウンロード結果（`download\<スペース識別名>_download.xlsx`、新スペースの実IDを含む）をアプリ名の一致で対応付け、`config\<スペース識別名>_config.xlsx`を生成する。kintoneへの書き込みは行わない（ローカルでのファイル生成のみ）。生成結果は次段階でそのままkintoneに反映されるファイルなので、この段階の後に内容を目視で確認・編集することを想定している。

アプリ名の対応付けは「どちらかの名前がどちらかを含むか」で1対1に判定する。対応付けられなかったアプリがある場合はコンソール・ログに警告を表示するので、必要ならconfigファイルに手動で追記する。

テンプレートのスペース名・アプリ名に含めた`{PH}`は、この段階でスペース識別名（`-DownloadConfigName`）に置き換えられる（kintone側でスペース・アプリを作成した時点ではまだ最終的な名前が決まらない、という運用を想定した仮の名前用のプレースホルダー）。

#### 処理の流れ

1. `generate-config-from-template.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `generate-config-from-template.ps1` が実行される
   1. テンプレート（`COMMON_TEMPLATE_PATH`配下）とダウンロード結果（`COMMON_DOWNLOAD_PATH`配下）を読み込む
   2. アプリ名の一致でテンプレートのアプリとダウンロード結果のアプリを対応付ける（対応付けられなかったアプリはコンソールに警告表示）
   3. スペース設定・メンバー・アプリ名・アプリACL・レコードACLをテンプレートの内容（スペース名・アプリ名は`{PH}`をスペース識別名に置き換えた値）で組み立てる
   4. `config\<スペース識別名>_config.xlsx`に書き出す
   5. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 引数

| 引数 | 説明 |
|---|---|
| `-TemplateConfigName` | 使用する設定テンプレート名（`template\<TEMPLATE_CONFIG_NAME>.xlsx`の`<TEMPLATE_CONFIG_NAME>`） |
| `-DownloadConfigName` | 対象のスペース識別名（`download\<DOWNLOAD_CONFIG_NAME>_download.xlsx`を読み込み、`config\<DOWNLOAD_CONFIG_NAME>_config.xlsx`に出力する） |

```bat
generate-config-from-template.bat -TemplateConfigName class-space -DownloadConfigName L20
```

指定しなかった引数は実行時にコンソールで入力を求められる。

#### 出力結果

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<スペース識別名>_config.xlsx` | 設定ファイルのフォルダ（`COMMON_CONFIG_PATH`） | kintoneに反映する設定内容（5シート構成）。テンプレートの`{PH}`置き換え部分は赤字で表示される |
| `generate_<スペース識別名>_yyyyMMdd_HHmmss.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ（対応付けられなかったアプリの警告もここに記録される） |

#### 注意点

> テンプレート側のアプリでダウンロード結果に対応するアプリが見つからない場合（またはその逆）、そのアプリはconfigに出力されない。処理自体は最後まで続行するが、終了コードは1（異常）になる。

> テンプレートに無い既存メンバー（スペース作成時にkintoneが自動追加する個人ユーザーなど）は、ダウンロード結果からそのまま引き継がれる（テンプレートに書いたメンバーを消してしまわないため）。

### 3. kintoneへ反映について

`config\<スペース識別名>_config.xlsx`の内容をkintoneに反映する。スペース単位（`space-settings`＝スペース設定、`space-member-list`＝スペースメンバー）と、アプリ単位（`space-app-list`＝アプリ名、`space-app-acl`＝アプリのアクセス権、`space-app-record-acl`＝レコードのアクセス権）を更新する。アプリの新規作成は行わない。

#### 処理の流れ

1. `apply-kintone-resources.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `apply-kintone-resources.ps1` が実行される
   1. kintoneにログインする
   2. `config\<スペース識別名>_config.xlsx`を読み込む
   3. スペースIDごとにスペース設定・メンバーを反映する
   4. アプリIDごとにアプリ名・アプリACL・レコードACLを反映し、変更したアプリはデプロイ（更新の反映）する
   5. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 引数

| 引数 | 説明 |
|---|---|
| `-ConfigName` | 対象のスペース識別名（`config\<CONFIG_NAME>_config.xlsx`の`<CONFIG_NAME>`） |
| `-Sheets` | 反映対象シート名（カンマ区切り、複数指定可）。省略時は5シートすべてが対象 |
| `-WhatIf` | 実際には反映せず、反映する内容だけをコンソール・ログに表示する |

```bat
apply-kintone-resources.bat -ConfigName L20
apply-kintone-resources.bat -ConfigName L20 -Sheets space-app-acl,space-app-record-acl
apply-kintone-resources.bat -ConfigName L20 -WhatIf
```

`-ConfigName`を指定しなかった場合は実行時にコンソールで入力を求められる。

#### 出力結果

ファイルへの出力は無い（反映先はkintone本体）。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `apply_<スペース識別名>_yyyyMMdd_HHmmss.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ（`-WhatIf`指定時は実際には反映されなかった内容として記録される） |

#### 注意点

> アプリIDが空の行（`space-app-list`）はスキップされる（このツールはアプリの新規作成をサポートしない）。

> 1つのアプリで名前・ACL・レコードACLのいずれかの設定に失敗した場合、そのアプリの更新（デプロイ）自体はスキップされる（一部だけが中途半端に反映されるのを避けるため）。個別の失敗はログにエラーとして記録され、処理全体は他のスペース・アプリの反映を続行する。

### 4. データチェックについて

`config\<スペース識別名>_config.xlsx`（期待値）とkintoneの現在の状態を比較し、差分を`checked\<スペース識別名>_check.xlsx`に出力する。読み取り専用で、kintoneへの書き込みは行わない。

#### 処理の流れ

1. `check-kintone-resources.bat` を実行する
2. `clients\set-env.bat` が呼び出され、環境変数の初期値がセットされる
3. `check-kintone-resources.ps1` が実行される
   1. kintoneにログインする
   2. `config\<スペース識別名>_config.xlsx`（期待値）を読み込む
   3. 同じ対象のkintoneの現在の状態を取得し、項目ごとに比較する
   4. 比較結果を`checked\<スペース識別名>_check.xlsx`に出力する
   5. ログの出力先（`COMMON_LOG_PATH`）に処理ログを出力する

#### 引数

| 引数 | 説明 |
|---|---|
| `-ConfigName` | 対象のスペース識別名（`config\<CONFIG_NAME>_config.xlsx`の`<CONFIG_NAME>`） |
| `-Sheets` | チェック対象シート名（カンマ区切り、複数指定可）。省略時は5シートすべてが対象 |

```bat
check-kintone-resources.bat -ConfigName L20
check-kintone-resources.bat -ConfigName L20 -Sheets space-app-acl
```

`-ConfigName`を指定しなかった場合は実行時にコンソールで入力を求められる。

#### 出力結果

ダウンロードファイルと同じ5シート構成。各シートは同じキー列に加えて、項目ごとの「`<項目名>_現状`」「`<項目名>_期待値`」列と、行全体の「結果」列を持つ。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<スペース識別名>_check.xlsx` | チェック結果の出力先（`COMMON_CHECK_OUTPUT_PATH`） | 期待値とkintoneの現状の比較結果 |
| `check_<スペース識別名>_yyyyMMdd_HHmmss.log` | ログの出力先（`COMMON_LOG_PATH`） | 処理内容のログ |

「結果」列の値：

| 値 | 意味 |
|---|---|
| 一致 | 期待値とkintoneの現状が一致している |
| 不一致 | 期待値とkintoneの現状が異なる項目がある（異なる項目のセルは赤字になる） |
| kintoneに未定義 | configに書かれているが、kintone側に対応する行（スペース／メンバー／アプリ／権限設定）が存在しない |
| 設定ファイルに未定義 | kintone側に存在するが、configに対応する行が無い |
| Everyoneの影響 | 「設定ファイルに未定義」のうち、現状の値がEveryone（全体）の期待値と完全に一致するもの（個別ユーザーへのEveryone権限の影響である可能性が高いことを示す参考情報） |

#### 注意点

> 「一致」「Everyoneの影響」以外の行が1件でもあれば、処理自体は最後まで続行するが終了コードは1（異常）になる。

## 設定ファイル・テンプレートの構成

`download\*_download.xlsx`・`config\*_config.xlsx`・`template\*.xlsx`は同じ5シート構成（`template`は`space-settings`の1行のみ、`space-app-list`はアプリ名の列のみを使う。スペースID・アプリID列は無視される）。

| シート名 | 内容 |
|---|---|
| `space-settings` | スペース全体の設定（1行） |
| `space-member-list` | スペースのメンバー（組織／グループ／ユーザー） |
| `space-app-list` | スペースに紐づくアプリの一覧（アプリ名） |
| `space-app-acl` | アプリのアクセス権（組織／グループ／ユーザーごと） |
| `space-app-record-acl` | レコードのアクセス権（条件＋組織／グループ／ユーザー／作成者ごと） |

`template\*.xlsx`のスペース名・アプリ名の列に`{PH}`を含めておくと、「2. 設定ファイルの生成」でスペース識別名に置き換えられる（例：`{PH}用スペース` → `L20用スペース`）。

## GUI版

`.bat`をコマンドプロンプトから実行する代わりに、画面から操作したい場合は`kintoneリソース生成ツール.exe`を使う（`build-gui.bat`でソース（`scripts\gui.ps1`）からビルドできる）。

### 実施手順

1. `kintoneリソース生成ツール.exe`をダブルクリックして起動する
2. 画面は「実行」「ログ」「設定」の3タブ。それぞれの使い方は以下を参照

### 実行タブ

「単体実行」と「一括実行」の2つの内部タブがある。

- 「スペース識別名」「スペーステンプレートID」「スペースID」「設定テンプレート名」の入力欄（「設定テンプレート名」は`COMMON_TEMPLATE_PATH`配下の`.xlsx`ファイル名の一覧から選ぶドロップダウン）
- 「詳細を表示」で0～4の各工程を個別に実行するボタン・状態表示が並ぶカードを開閉できる（初期状態は非表示）
- 各工程のカードには「実行」ボタン（その工程だけを実行）、状態表示（未実行/実行中.../成功/失敗）、出力ファイルがある工程（1・2・4）には結果ファイルを開く「開く」ボタンがある
- 「まとめて実行」ボタンで0→4を順番に実行する。「0. スペース作成」が成功すると、作成されたスペースIDが「スペースID」欄に自動入力される
- いずれかの工程が失敗した場合はそこで中断し、後続の工程は実行しない
- 実行結果はすべて画面下部のログ欄に追記表示される（実行するたびに積み重なり、過去の実行結果も遡って確認できる）
- 実行中は他のタブへの切り替えを含め、画面の操作ができなくなる（完了するまで待つ必要がある）

#### 一括実行

- 「参照...」で選んだExcelファイル（列は「スペース識別名」「スペーステンプレートID」「設定テンプレート名」）の各行について、上の入力欄に値をセットしてから0→4を順に実行する
- いずれかの必須項目が空の行はスキップする
- 1行の失敗（またはスキップ）があっても後続の行の処理は続行し、完了後に全行分の結果（成功/失敗/スキップ）を一覧でログに出力する

### ログタブ

- 「スペース識別名」ドロップダウンで、表示するログをスペース識別名別に絞り込める。「すべて」を選べば絞り込みなし
- 「0. スペース作成」～「4. データチェック」のラジオボタンで、確認したい工程のログを切り替える
- 選んだ工程・スペース識別名に一致するログファイル（`COMMON_LOG_PATH`配下、`<ステージ名>_<スペース識別名>_yyyyMMdd_HHmmss.log`）を、更新日時の古い順にすべて連結して表示する

### 設定タブ

- `clients\set-env.bat`の内容（各フォルダパスの5項目）と、`clients\set-kintone.bat`の内容（kintoneの接続情報3項目）を一覧表示し、値を書き換えて「保存」で書き込める。テキストエディタで直接編集する代わりに使える。フォルダの項目は「参照...」ボタンでダイアログから選べる。パスワードは入力時に非表示になる
- 各項目のラベルは環境変数名ではなく日本語の表示名を表示する
- 「再読込」で現在の`clients\set-env.bat`/`clients\set-kintone.bat`の内容を読み直す（保存前の変更を取り消したい場合など）
- `clients\set-kintone.bat`が存在しない場合でも接続情報欄は空欄で表示され、「保存」を押すと新規作成される。詳しくは[clients\README.md](clients/README.md)を参照
- 「接続テスト」ボタンで、その時点で入力欄に入っているサイトURL・ログイン名・パスワード（保存前の値でよい）でkintoneにログインできるか確認できる。結果は「保存」と同じ位置に成功/失敗（失敗時はエラー内容も）が表示される。このボタンではファイルへの保存は行われない

| 環境変数名 | 表示名 |
|---|---|
| `COMMON_DOWNLOAD_PATH` | ダウンロード先のフォルダ |
| `COMMON_TEMPLATE_PATH` | テンプレートファイルのフォルダ |
| `COMMON_CONFIG_PATH` | 設定ファイルのフォルダ |
| `COMMON_CHECK_OUTPUT_PATH` | チェック結果の出力先フォルダ |
| `COMMON_LOG_PATH` | ログの出力先フォルダ |
| `KINTONE_BASE_URL` | kintoneのサイトURL |
| `KINTONE_LOGIN` | ログイン名 |
| `KINTONE_PASSWORD` | パスワード |

### 必要なもの

> PowerShellモジュール「ImportExcel」が必要（Excelの読み書きに使用）。自動インストールは行われないため、未インストールの場合は事前に`Install-Module ImportExcel -Scope CurrentUser`を実行しておくこと。

> GUI版を自分でビルドする場合はPowerShellモジュール「ps2exe」が必要。未インストールの場合、`build-gui.bat`実行時に自動でインストールされる（初回はインターネット接続とインストール確認が必要）。

### 注意点

> kintoneのログイン情報（`KINTONE_LOGIN`/`KINTONE_PASSWORD`）が未設定の場合、GUIはコンソールを持たないため入力プロンプトを表示できない。GUI版を使う場合は`clients\set-kintone.bat`でログイン情報を設定しておくこと（書き方は[clients\README.md](clients/README.md)を参照）。
