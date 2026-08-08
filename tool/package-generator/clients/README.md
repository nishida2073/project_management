# set-env.bat・クライアントプロファイルの書き方

`set-env.bat`（環境変数の既定値。ツールのルートから`call clients\set-env.bat`で呼び出される）と、
クライアントごとに変わる値だけを上書きするファイルを置くフォルダ。

## ファイルの作り方

GUI版の「設定」タブから作成・編集できる（「クライアント」ドロップダウンでクライアントを選ぶか、「新規作成...」で新しいクライアントを作る）。

手動でファイルを作る場合は、このフォルダに`set-env-<クライアント名>.bat`を作成し、上書きしたい変数だけを`set "VAR=値"`で書く。

- 上書きできるのは、ログ関連（`COMMON_LOG_PATH`/`DOWNLOAD_LOG_PREFIX`/`GENERATE_LOG_PREFIX`/`UPLOAD_LOG_PREFIX`）以外の全項目（[ツールのREADME](../README.md)の環境変数一覧を参照）。
- 書かなかった変数は`set-env.bat`の値がそのまま使われる。
- ファイル名の`set-env-`より後ろの部分（拡張子`.bat`を除く）がGUIのドロップダウンに表示される。
- `if not defined`ではなく`set`（無条件の上書き）を使うこと。GUI側はこのファイルの値を必ず優先させる。
  - 例外：`DOWNLOAD_ENABLED`/`GENERATE_ENABLED`/`UPLOAD_ENABLED`の3項目だけは`if not defined VAR set "VAR=値"`（`set-env.bat`と同じ書き方）で書く。実行タブのチェックボックス（または`set-env.bat`の既定値）が先に定義済みのため、この3行は実質無視され、実行時にはチェックボックス側が優先される。GUIの「設定」タブから保存すると自動でこの形式になる。
- ここに書いたファイルは`set-env.bat`自体を書き換えない。GUIを実行するたびに一時的に反映されるだけなので、クライアントを切り替えても`set-env.bat`の内容は元のまま。

## `.bat`から直接使う場合

GUIを使わず`.bat`をコマンドラインから直接実行する場合も、`client=<クライアント名>`引数でクライアントを指定できる。

```bat
all.bat "client=コースA"
download-folder.bat "client=コースA"
generate-package.bat "client=コースA"
upload-folder.bat "client=コースA"
```

`generate-package.bat`は`include=`/`exclude=`と組み合わせられる（順不同）。

```bat
generate-package.bat "client=コースA" "include=対象シート1"
```

指定しない場合（引数無し）は`set-env.bat`の値のまま。存在しないクライアント名を指定した場合は何も上書きされず、`set-env.bat`の値のまま実行される。

## ログファイル名・ログ内容にクライアント名が入る

GUIの「実行」タブでクライアントを選ぶか、`.bat`に`client=`引数を渡して実行すると、ログファイル名に`<クライアント名>_`が挟まる（例：`ダウンロード_コースA_原本.log`）。同じような`DOWNLOAD_SITE_PATH`（例：どちらも「原本」で終わる）を持つ別クライアントのログファイルが衝突しないようにするため。クライアントを指定しない場合は`デフォルト_`が挟まる（例：`ダウンロード_デフォルト_原本.log`）。

ログファイルの内容にも「# 実行情報」の`バッチ名`の前に`クライアント: <クライアント名>`の行が入る。クライアントを指定しない場合は`クライアント: デフォルト`になる。

GUIの「ログ」タブの「クライアント」ドロップダウンには「すべて」「デフォルト」に加えて既存のクライアントが並ぶ。「デフォルト」を選ぶとクライアント未指定で実行した分のログだけに絞り込める。

## 注意点

> `DOWNLOAD_ENABLED`/`GENERATE_ENABLED`/`UPLOAD_ENABLED`の3項目以外は、`if not defined VAR set "VAR=値"`（`set-env.bat`と同じ書き方）ではなく、`set "VAR=値"`（無条件）で書くこと。この3項目だけは逆に`if not defined`で書く（上のファイルの作り方を参照）。

> `set-env.bat`自身が`%~dp0`（自分の場所）から`BASE_PATH`を計算しているため、`set-env.bat`を別の場所に移動する場合は`clients`フォルダの1つ上がツールのルートになるように置くこと。
