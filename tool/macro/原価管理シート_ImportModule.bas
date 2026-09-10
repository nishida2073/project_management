Option Explicit

Sub CloseThisSheet()
    Dim currentSheet As Worksheet
    Set currentSheet = ActiveSheet

    If currentSheet.Name <> "Index" Then
        currentSheet.Visible = xlSheetHidden
        Sheets("個人計画Index").Activate
    End If
End Sub

' ============================
' 実績Excelを読み込んで実績を反映する
' ============================
Sub ImportFromOtherBook()

    Dim wbOther As Workbook
    Dim wsOther As Worksheet
    Dim wsMain As Worksheet
    Dim lastRow As Long
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

    ' === ① ファイルダイアログで Other を選ぶ ===
    f = Application.GetOpenFilename("Excelファイル (*.xlsx), *.xlsx")

    If f = False Then
        MsgBox "キャンセルされました"
        Exit Sub
    End If

    ' === ② Otherブックを開く ===
    Set wbOther = Workbooks.Open(f, ReadOnly:=True)
    Set wsOther = wbOther.Sheets("実績")   ' ←読み込み元
    Set wsMain = ThisWorkbook.Sheets("計画算定シート") ' ←貼り付け先

    ' === ③ マッピングは1回だけ読み込む ===
    Set mapOtherCol = LoadMappingHorizontal("実績Excel")
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")
    Set mapOtherRange = LoadMappingHorizontal("実績Excel貼付範囲")
    Set mapMainCol = LoadMappingHorizontal("原価管理Excel")
    Set mapQ = LoadMappingHorizontal("会計区分1マッピング")
    Set mapR = LoadMappingHorizontal("会計区分2マッピング")

    ' === ④ Main側を1回だけスキャンして検索用インデックスを作る ===
    Set mainIndex = BuildMainIndex(wsMain, mapMainCol)

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    On Error GoTo CleanFail

    ' === ⑤ Otherの可変範囲の最終行取得 ===
    lastRow = wsOther.Cells(wsOther.Rows.Count, mapOtherCol("年度")).End(xlUp).Row

    ' === ⑥ 行ループ ===
    For r = 2 To lastRow

        ' キー4つ取得（年度, 案件ID, 区分, 原価区分ID）
        key1 = wsOther.Cells(r, mapOtherCol("年度")).Value
        key2 = wsOther.Cells(r, mapOtherCol("案件ID")).Value
        key3 = Trim(CStr(wsOther.Cells(r, mapOtherCol("区分")).Value))
        key4 = Trim(CStr(wsOther.Cells(r, mapOtherCol("原価区分ID")).Value))

        If mapQ.Exists(key3) And mapR.Exists(key4) Then

            yOther = NormalizeYear(key1)
            qMain = mapQ(key3)
            rMain = mapR(key4)
            idxKey = yOther & "|" & key2 & "|" & qMain & "|" & rMain

            ' === ⑦ Dictionaryで一致する行を即座に取得 ===
            If mainIndex.Exists(idxKey) Then
                foundRow = mainIndex(idxKey)

                ' === ⑧ 一致した行に貼り付け（値が変わったセルだけ赤色にする） ===
                Set mainRange = wsMain.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)
                Set otherRange = wsOther.Range(mapOtherRange("開始") & r & ":" & mapOtherRange("終了") & r)

                oldVals = mainRange.Value          ' 上書き前の値を保持
                mainRange.Value = otherRange.Value  ' 一括で貼り付け
                newVals = mainRange.Value

                HighlightChangedCells mainRange, oldVals, newVals
            End If

        End If

    Next r

CleanExit:
    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    If Not wbOther Is Nothing Then wbOther.Close SaveChanges:=False
    Exit Sub

CleanFail:
    MsgBox "エラーが発生しました: " & Err.Description
    Resume CleanExit

End Sub


' ============================
' Main側の「年度|案件ID|会計区分1|会計区分2」→行番号 の索引を作る
' ============================
Function BuildMainIndex(ws As Worksheet, mapMainCol As Object) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    Dim colYear As Variant, colCase As Variant, colQ As Variant, colR As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colQ = mapMainCol("会計区分1")
    colR = mapMainCol("会計区分2")
    colYojitsu = mapMainCol("予実")

    Dim lastRow As Long, r As Long
    lastRow = ws.Cells(ws.Rows.Count, colYear).End(xlUp).Row

    For r = 5 To lastRow
        If ws.Cells(r, colYojitsu).Value = "実績" Then
            Dim k As String
            k = ws.Cells(r, colYear).Value & "|" & ws.Cells(r, colCase).Value & "|" & _
                ws.Cells(r, colQ).Value & "|" & ws.Cells(r, colR).Value

            ' 同一キーが複数行ある場合は最初に見つかった行を採用（元の実装と同じ挙動）
            If Not dic.Exists(k) Then dic(k) = r
        End If
    Next r

    Set BuildMainIndex = dic
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
            If CStr(oldVals(1, i)) <> CStr(newVals(1, i)) Then
                rng.Cells(i).Font.Color = vbRed
            Else
                rng.Cells(i).Font.ColorIndex = xlAutomatic
            End If
        Next i
    Else
        ' 範囲が1セルだけの場合、Valueは配列でなくスカラーになる
        If CStr(oldVals) <> CStr(newVals) Then
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
