Option Explicit

' 直前の実績反映で上書きした行のバックアップ（行番号 → Array(旧値, 旧フォント色)）
Private gBackupRows As Object

Sub CloseThisSheet()
    Dim currentSheet As Worksheet
    Set currentSheet = ActiveSheet

    If currentSheet.Name <> "Index" Then
        currentSheet.Visible = xlSheetHidden
        Sheets("個人計画Index").Activate
    End If
End Sub

' ============================
' Workbook_Openの本体処理
' ============================
Sub HandleWorkbookOpen()

    Dim isBrowser As Boolean
    isBrowser = (Application.OperatingSystem = "")

    If isBrowser Then Exit Sub

    EnsureButtonsExist

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets("計画算定シート")

    If wsMain.Visible = xlSheetVisible Then
        wsMain.Range("A1").Select
    End If

End Sub


' ============================
' Workbook_BeforeSaveの本体処理（貼り付け範囲の黒字化）
' ============================
Sub HandleBeforeSave()

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("計画算定シート")
    Dim mapMainRange As Object

    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")

    Dim lastRow As Long
    lastRow = ws.Cells.SpecialCells(xlCellTypeLastCell).Row   ' Ctrl+Shift+End と同じ判定

    If lastRow >= 5 Then
        ws.Range(mapMainRange("開始") & "5:" & mapMainRange("終了") & lastRow).Font.Color = vbBlack
    End If

End Sub


' ============================
' 計画算定シートに実績反映・元に戻すボタンが無ければ作成する。
' Workbook_Open、および Workbook_BeforeClose がボタン削除後に予約する
' 復元チェック（Application.OnTimeの呼び出し先は標準モジュールである必要があるため、ここに置く）
' の両方から呼ばれる
' ============================
Sub EnsureButtonsExist()

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets("計画算定シート")

    If wsMain.Visible <> xlSheetVisible Then Exit Sub

    CreateButton wsMain, "MacroProcButton999", "D2", "実績反映", "ImportFromOtherBook"
    CreateButton wsMain, "UndoProcButton999", "E2", "元に戻す", "UndoLastImport"

End Sub


' ============================
' フォームコントロールのボタンを作成し、指定セルの左上に配置してマクロを割り当てる
' ============================
Sub CreateButton(wsMain As Worksheet, buttonName As String, targetCellAddress As String, caption As String, macroName As String)

    ' 同名の図形が既に残っている場合は先に削除しておく（名前の衝突を防ぐ）
    DeleteButtonIfExists wsMain, buttonName

    Dim targetCell As Range
    Set targetCell = wsMain.Range(targetCellAddress)

    Dim btn As Button
    Set btn = wsMain.Buttons.Add(targetCell.Left, targetCell.Top, 60, 20)

    btn.Name = buttonName
    btn.Caption = caption
    btn.OnAction = macroName

    With btn.Characters.Font
        .Name = "Meiryo UI"
        .Size = 9
        .Bold = True
    End With

End Sub


' ============================
' Workbook_BeforeCloseの本体処理（ボタン削除＋復元チェックの予約）
' ============================
Sub HandleBeforeClose()

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets("計画算定シート")

    DeleteButtonIfExists wsMain, "MacroProcButton999"
    DeleteButtonIfExists wsMain, "UndoProcButton999"

    ' このあと「変更を保存しますか？」でキャンセルされ、閉じずに残る場合に備えて
    ' 少し後にボタンが残っているか確認・復元する処理を予約しておく
    Application.OnTime Now, "'" & ThisWorkbook.Name & "'!EnsureButtonsExist"

End Sub


' ============================
' 指定名のボタンがシート上に存在すれば削除する
' ============================
Sub DeleteButtonIfExists(ws As Worksheet, buttonName As String)

    Dim shp As Shape
    On Error Resume Next
    Set shp = ws.Shapes(buttonName)
    On Error GoTo 0

    If Not shp Is Nothing Then
        shp.Delete
    End If

End Sub

' ============================
' 実績Excelを読み込んで実績を反映する
' ============================
Sub ImportFromOtherBook()

    Dim wbOther As Workbook
    Dim wsOther As Worksheet
    Dim wsMain As Worksheet
    Dim lastRowOther As Long
    Dim lastRowMain As Long
    Dim r As Long
    Dim key1 As Variant, key2 As Variant, key3 As Variant, key4 As Variant
    Dim foundRow As Long
    Dim f As Variant

    Dim mapOtherCol As Object
    Dim mapMainRange As Object
    Dim mapOtherRange As Object
    Dim mapMainCol As Object
    Dim mapQ As Object
    Dim mapR As Object
    Dim mainIndex As Object

    Dim yOther As Long
    Dim qMain As String, rMain As String
    Dim idxKey As String

    Dim mainRange As Range, otherRange As Range
    Dim oldVals As Variant, newVals As Variant
    Dim completed As Boolean
    Dim matchedRows As Object

    Dim years As Variant, caseIds As Variant, kubuns As Variant, costKubuns As Variant

    ' === ① ファイルダイアログで Other を選ぶ ===
    f = Application.GetOpenFilename("Excelファイル (*.xlsx), *.xlsx")

    If f = False Then Exit Sub

    ' === ② Otherブックを開く ===
    Set wbOther = Workbooks.Open(f, ReadOnly:=True)

    ' ここ以降のエラーは全て CleanFail で拾い、Otherブックを必ず閉じる
    On Error GoTo CleanFail

    If Not SheetExists(wbOther, "実績") Then
        MsgBox "選択したファイルに「実績」シートが見つかりません。" & vbCrLf & _
               "ファイルが正しいか確認してください。", vbExclamation
        GoTo CleanExit
    End If

    Set wsOther = wbOther.Sheets("実績")   ' ←読み込み元
    Set wsMain = ThisWorkbook.Sheets("計画算定シート") ' ←貼り付け先

    ' === ③ マッピングは1回だけ読み込む ===
    Set mapOtherCol = LoadMappingHorizontal("実績Excel")
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")
    Set mapOtherRange = LoadMappingHorizontal("実績Excel貼付範囲")
    Set mapMainCol = LoadMappingHorizontal("原価管理Excel")
    Set mapQ = LoadMappingHorizontal("会計区分1マッピング")
    Set mapR = LoadMappingHorizontal("会計区分2マッピング")

    ' === ④ Main側の最終行を取得し、検索用インデックスを作る ===
    lastRowMain = wsMain.Cells(wsMain.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    Set mainIndex = BuildMainIndex(wsMain, mapMainCol, lastRowMain)

    ' 今回の実行分のバックアップを新規に用意（前回分は破棄）
    Set gBackupRows = CreateObject("Scripting.Dictionary")
    Set matchedRows = CreateObject("Scripting.Dictionary")

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    ' === ⑤ Otherの可変範囲の最終行を取得し、必要な列を一括で配列に読み込む ===
    lastRowOther = wsOther.Cells(wsOther.Rows.Count, mapOtherCol("年度")).End(xlUp).Row

    If lastRowOther >= 2 Then
        years = wsOther.Range(wsOther.Cells(1, mapOtherCol("年度")), wsOther.Cells(lastRowOther, mapOtherCol("年度"))).Value
        caseIds = wsOther.Range(wsOther.Cells(1, mapOtherCol("案件ID")), wsOther.Cells(lastRowOther, mapOtherCol("案件ID"))).Value
        kubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("区分")), wsOther.Cells(lastRowOther, mapOtherCol("区分"))).Value
        costKubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("原価区分ID")), wsOther.Cells(lastRowOther, mapOtherCol("原価区分ID"))).Value
    End If

    ' === ⑥ 行ループ（キーの判定は配列上で行い、一致した行だけシートへアクセスする） ===
    For r = 2 To lastRowOther

        ' キー4つ取得（年度, 案件ID, 区分, 原価区分ID）
        key1 = years(r, 1)
        key2 = caseIds(r, 1)
        key3 = Trim(CStr(kubuns(r, 1)))
        key4 = Trim(CStr(costKubuns(r, 1)))

        If mapQ.Exists(key3) And mapR.Exists(key4) Then

            yOther = NormalizeYear(key1)
            qMain = mapQ(key3)
            rMain = mapR(key4)
            idxKey = yOther & "|" & key2 & "|" & qMain & "|" & rMain

            ' === ⑦ Dictionaryで一致する行を即座に取得 ===
            If mainIndex.Exists(idxKey) Then
                foundRow = mainIndex(idxKey)

                ' 実績シート側に重複行があり、同じ行へ既に反映済みの場合は再処理しない
                ' （2回目以降の処理が「1回目で上書きした後の値」を元に比較してしまい、
                '   正しく付いた赤色やUndo用バックアップが誤って上書きされるため）
                If Not matchedRows.Exists(foundRow) Then
                    matchedRows(foundRow) = True

                    ' === ⑧ 一致した行に貼り付け（値が変わったセルだけ赤色にする） ===
                    Set mainRange = wsMain.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)
                    Set otherRange = wsOther.Range(mapOtherRange("開始") & r & ":" & mapOtherRange("終了") & r)

                    Dim oldColors As Variant
                    oldColors = GetFontColors(mainRange)   ' 上書き前のフォント色を保持

                    oldVals = mainRange.Value          ' 上書き前の値を保持
                    mainRange.Value = otherRange.Value  ' 一括で貼り付け
                    newVals = mainRange.Value

                    gBackupRows(foundRow) = Array(oldVals, oldColors)

                    HighlightChangedCells mainRange, oldVals, newVals
                End If
            End If

        End If

    Next r

    ' === ⑨ 一度もマッチしなかった「予実=実績」行をグレー表示にする ===
    MarkUnmatchedActualRows wsMain, mapMainCol, mapMainRange, matchedRows, gBackupRows, lastRowMain

    completed = True

CleanExit:
    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    If Not wbOther Is Nothing Then wbOther.Close SaveChanges:=False

    If completed Then MsgBox "実績反映が完了しました。", vbInformation

    Exit Sub

CleanFail:
    MsgBox "エラーが発生しました: " & Err.Description
    Resume CleanExit

End Sub


' ============================
' 直前の実績反映を元に戻す
' ============================
Sub UndoLastImport()

    Dim noHistory As Boolean
    noHistory = (gBackupRows Is Nothing)
    If Not noHistory Then noHistory = (gBackupRows.Count = 0)

    If noHistory Then
        MsgBox "実行履歴がありません。"
        Exit Sub
    End If

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets("計画算定シート")

    Dim mapMainRange As Object
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    Dim key As Variant
    For Each key In gBackupRows.Keys
        Dim foundRow As Long
        foundRow = key

        Dim rng As Range
        Set rng = wsMain.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)

        Dim backupData As Variant
        backupData = gBackupRows(key)

        Dim oldVals As Variant, oldColors As Variant
        oldVals = backupData(0)
        oldColors = backupData(1)

        rng.Value = oldVals
        SetFontColors rng, oldColors
    Next key

    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    Set gBackupRows = Nothing

    MsgBox "直前の実績反映を元に戻しました。"

End Sub


' ============================
' 範囲内の各セルのフォント色を配列として取得する
' ============================
Function GetFontColors(rng As Range) As Variant
    Dim arr() As Long
    Dim i As Long

    ReDim arr(1 To rng.Cells.Count)
    For i = 1 To rng.Cells.Count
        arr(i) = rng.Cells(i).Font.Color
    Next i

    GetFontColors = arr
End Function


' ============================
' 予実=実績だが、今回の実行で一度も実績シート側とマッチしなかった行をグレー表示にする
' ============================
Sub MarkUnmatchedActualRows(ws As Worksheet, mapMainCol As Object, mapMainRange As Object, matchedRows As Object, backupRows As Object, lastRow As Long)
    If lastRow < 5 Then Exit Sub

    Dim colYojitsu As Variant
    colYojitsu = mapMainCol("予実")

    Dim yojitsus As Variant
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim r As Long
    For r = 5 To lastRow
        If yojitsus(r, 1) = "実績" Then
            If Not matchedRows.Exists(r) Then
                Dim rng As Range
                Set rng = ws.Range(mapMainRange("開始") & r & ":" & mapMainRange("終了") & r)

                ' グレーにする前の値・フォント色をバックアップしておく（元に戻すため）
                If Not backupRows.Exists(r) Then
                    backupRows(r) = Array(rng.Value, GetFontColors(rng))
                End If

                rng.Font.Color = RGB(150, 150, 150)
            End If
        End If
    Next r
End Sub


' ============================
' GetFontColors で取得した配列を範囲に書き戻す
' ============================
Sub SetFontColors(rng As Range, colors As Variant)
    Dim i As Long
    For i = 1 To rng.Cells.Count
        rng.Cells(i).Font.Color = colors(i)
    Next i
End Sub


' ============================
' Main側の「年度|案件ID|会計区分1|会計区分2」→行番号 の索引を作る
' ============================
Function BuildMainIndex(ws As Worksheet, mapMainCol As Object, lastRow As Long) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    If lastRow < 5 Then
        Set BuildMainIndex = dic
        Exit Function
    End If

    Dim colYear As Variant, colCase As Variant, colQ As Variant, colR As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colQ = mapMainCol("会計区分1")
    colR = mapMainCol("会計区分2")
    colYojitsu = mapMainCol("予実")

    Dim years As Variant, caseIds As Variant, qs As Variant, rs As Variant, yojitsus As Variant
    years = ws.Range(ws.Cells(1, colYear), ws.Cells(lastRow, colYear)).Value
    caseIds = ws.Range(ws.Cells(1, colCase), ws.Cells(lastRow, colCase)).Value
    qs = ws.Range(ws.Cells(1, colQ), ws.Cells(lastRow, colQ)).Value
    rs = ws.Range(ws.Cells(1, colR), ws.Cells(lastRow, colR)).Value
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim r As Long
    For r = 5 To lastRow
        If yojitsus(r, 1) = "実績" Then
            Dim k As String
            k = years(r, 1) & "|" & caseIds(r, 1) & "|" & qs(r, 1) & "|" & rs(r, 1)

            If dic.Exists(k) Then
                Err.Raise vbObjectError + 1001, _
                          "BuildMainIndex", _
                          "計画算定シートに、条件が重複する行があります。" & vbCrLf & _
                          "行" & dic(k) & "と行" & r & "が、年度・案件ID・会計区分1・会計区分2の組み合わせで重複しています。" & vbCrLf & _
                          "実績反映を行う前に、計画算定シート側の重複を解消してください。"
            End If

            dic(k) = r
        End If
    Next r

    Set BuildMainIndex = dic
End Function


' ============================
' 指定した名前のシートがブックに存在するか調べる
' ============================
Function SheetExists(wb As Workbook, sheetName As String) As Boolean
    Dim ws As Worksheet
    For Each ws In wb.Sheets
        If ws.Name = sheetName Then
            SheetExists = True
            Exit Function
        End If
    Next ws
    SheetExists = False
End Function


' ============================
' Other側の日付/年から年だけを安全に取り出す
' ============================
Function NormalizeYear(k1 As Variant) As Long
    If IsDate(k1) Then
        NormalizeYear = Year(CDate(k1))
    ElseIf IsNumeric(k1) Then
        NormalizeYear = CLng(k1)
    Else
        NormalizeYear = -1
    End If
End Function


' ============================
' 貼り付け前後で値が変わったセルだけ赤字にする
' （変わっていないセルは自動色に戻す）
' ============================
Sub HighlightChangedCells(rng As Range, oldVals As Variant, newVals As Variant)
    Dim i As Long

    If IsArray(oldVals) Then
        For i = 1 To rng.Cells.Count
            If CStr(newVals(1, i)) = "" Then
                ' 実績シート側にその値が存在しなかった
                rng.Cells(i).Font.Color = RGB(150, 150, 150)
            ElseIf CStr(oldVals(1, i)) <> CStr(newVals(1, i)) Then
                rng.Cells(i).Font.Color = vbRed
            Else
                rng.Cells(i).Font.ColorIndex = xlAutomatic
            End If
        Next i
    Else
        ' 範囲が1セルだけの場合、Valueは配列でなくスカラーになる
        If CStr(newVals) = "" Then
            rng.Font.Color = RGB(150, 150, 150)
        ElseIf CStr(oldVals) <> CStr(newVals) Then
            rng.Font.Color = vbRed
        Else
            rng.Font.ColorIndex = xlAutomatic
        End If
    End If
End Sub


' ============================
' 指定ヘッダーの「下方向2列」を辞書に読み込む
' ============================
Function LoadMappingHorizontal(headerText As String) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("システム用")

    Dim lastCol As Long
    lastCol = ws.Cells(5, ws.Columns.Count).End(xlToLeft).Column

    Dim c As Long
    Dim found As Boolean

    ' 5行目の横方向を走査してヘッダーを探す
    For c = 1 To lastCol
        If ws.Cells(5, c).Value = headerText Then
            found = True

            Dim r As Long
            r = 6 ' マッピングは6行目から始まる

            ' 空行に当たるまで読み込む
            Do While ws.Cells(r, c).Value <> ""
                Dim key As String
                Dim val As String

                key = ws.Cells(r, c).Value
                val = ws.Cells(r, c + 1).Value ' 右隣の列が値

                If key <> "" Then dic(key) = val

                r = r + 1
            Loop

            Exit For
        End If
    Next c

    ' ★ ヘッダーが見つからなかった場合は強制終了
    If Not found Then
        Err.Raise vbObjectError + 1000, _
                  "LoadMappingHorizontal", _
                  "ヘッダー「" & headerText & "」が見つかりません。"
    End If

    Set LoadMappingHorizontal = dic
End Function
