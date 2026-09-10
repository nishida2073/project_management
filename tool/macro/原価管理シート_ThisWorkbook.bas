Option Explicit

Private Sub Workbook_Open()

    Dim isBrowser As Boolean
    isBrowser = (Application.OperatingSystem = "")

    If isBrowser Then Exit Sub

    Dim wsMain As Worksheet
    Set wsMain = Sheets("計画算定シート")

    ' シートが非表示の間はボタンを作らない（後段のSelectが失敗するため）
    If wsMain.Visible <> xlSheetVisible Then Exit Sub

    CreateButton wsMain, "MacroProcButton999", "D2", "実績反映", "ImportFromOtherBook"
    CreateButton wsMain, "UndoProcButton999", "F2", "元に戻す", "UndoLastImport"

    wsMain.Range("A1").Select

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
    Set btn = wsMain.Buttons.Add(targetCell.Left, targetCell.Top, 80, 20)

    btn.Name = buttonName
    btn.Caption = caption
    btn.OnAction = macroName

    With btn.Characters.Font
        .Name = "Meiryo UI"
        .Size = 9
        .Bold = True
    End With

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
