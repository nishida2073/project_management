Option Explicit

Private Sub Workbook_Open()

    Dim isBrowser As Boolean
    isBrowser = (Application.OperatingSystem = "")

    If isBrowser Then Exit Sub

    Dim wsMain As Worksheet
    Set wsMain = Sheets("計画算定シート")

    ' シートが非表示の間はボタンを作らない（Activate できないため）
    If wsMain.Visible <> xlSheetVisible Then Exit Sub

    CreateButtonFromTemplate wsMain, "MacroProcButton999", "D2"
    CreateButtonFromTemplate wsMain, "UndoProcButton999", "F2"

    wsMain.Range("A1").Select

End Sub


' ============================
' システム用シートにある同名テンプレート図形をコピーして
' wsMain上の指定セル（targetCellAddress）の左上に貼り付ける
' ============================
Sub CreateButtonFromTemplate(wsMain As Worksheet, buttonName As String, targetCellAddress As String)

    Dim shp As Shape
    On Error Resume Next
    Set shp = Sheets("システム用").Shapes(buttonName)
    On Error GoTo 0

    If shp Is Nothing Then
        MsgBox "「システム用」シートにテンプレート「" & buttonName & "」が見つかりません。", vbExclamation
        Exit Sub
    End If

    ' 同名の図形が既に残っている場合は先に削除しておく（名前の衝突を防ぐ）
    DeleteButtonIfExists wsMain, buttonName

    Dim targetCell As Range
    Set targetCell = wsMain.Range(targetCellAddress)

    shp.Copy
    DoEvents

    wsMain.Activate

    Dim pasted As Shape
    Dim retry As Integer
    Dim success As Boolean
    Dim beforeCount As Long
    Dim pasteFailed As Boolean

    ' 最大3回リトライ
    For retry = 1 To 3

        beforeCount = wsMain.Shapes.Count

        On Error Resume Next
        Err.Clear
        wsMain.Paste
        pasteFailed = (Err.Number <> 0)
        On Error GoTo 0

        DoEvents

        ' 「エラーが出ていない」かつ「図形の数が実際に増えた」ことで成功を判定する
        If Not pasteFailed And wsMain.Shapes.Count > beforeCount Then
            Set pasted = wsMain.Shapes(wsMain.Shapes.Count)
            success = True
            Exit For
        End If

        ' 失敗したら少し待つ
        Application.Wait Now + TimeValue("0:00:01")
    Next retry

    If Not success Then
        MsgBox "「" & buttonName & "」の貼り付けに失敗しました。", vbExclamation
        Exit Sub
    End If

    pasted.Left = targetCell.Left
    pasted.Top = targetCell.Top
    pasted.Name = buttonName

End Sub


Private Sub Workbook_BeforeSave(ByVal SaveAsUI As Boolean, Cancel As Boolean)

    Dim ws As Worksheet
    Set ws = Sheets("計画算定シート")
    Dim mapMainRange As Object

    ' ★ 貼り付け範囲の 5行目～最終行まで黒字化
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")

    Dim lastRow As Long
    lastRow = ws.Cells.SpecialCells(xlCellTypeLastCell).Row   ' Ctrl+Shift+End と同じ判定

    If lastRow >= 5 Then
        ws.Range(mapMainRange("開始") & "5:" & mapMainRange("終了") & lastRow).Font.Color = vbBlack
    End If

End Sub


Private Sub Workbook_BeforeClose(Cancel As Boolean)

    Dim wsMain As Worksheet
    Set wsMain = Sheets("計画算定シート")

    DeleteButtonIfExists wsMain, "MacroProcButton999"
    DeleteButtonIfExists wsMain, "UndoProcButton999"

End Sub


Sub DeleteButtonIfExists(ws As Worksheet, buttonName As String)

    Dim shp As Shape
    On Error Resume Next
    Set shp = ws.Shapes(buttonName)
    On Error GoTo 0

    If Not shp Is Nothing Then
        shp.Delete
    End If

End Sub
