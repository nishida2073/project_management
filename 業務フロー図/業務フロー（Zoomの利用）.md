# Zoom利用フロー

## 概要

Zoomミーティングの作成から、起動・参加、ブレイクアウトルーム作成までの一連の業務フローです。

- ミーティングの作成
- ミーティングの起動と権限の設定
- ミーティングへの参加
- ブレイクアウトルームの作成

各業務は、発生タイミングや条件ごとに複数の図に分割し、担当者（レーン）ごとの流れを示しています。

**凡例**

- レーン（枠）：運営（SO）（紫）／講師（緑）／受講生（黄土）
- 各業務は、発生タイミングや条件（研修開催前・当日など）ごとに複数の図に分けています。各見出し直下の説明文が、その図が発生する条件です。
- 黄色い点線枠：元資料の注記（補足事項）

---

## 1. ミーティングの作成

研修開催前に、運営（SO）がミーティングを作成し講師と共有する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["運営（SO）"]
        direction TB
        N1["1. ミーティングの作成<br/>Zoom"]:::so
        N2["2. ミーティング情報の共有<br/>kintoneアプリ"]:::so
        N1 --> N2
    end
    subgraph G2["講師"]
        direction TB
        N3["3. ミーティング情報の確認<br/>kintoneアプリ"]:::instr
        N4["4. ミーティング情報の変更<br/>Zoom"]:::instr
        N3 --> N4
    end

    N2 --> N3

    classDef so fill:#6b5b8a,color:#000;
    classDef instr fill:#4c7a5d,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1,G2 lane;
```

### 作業

1. ミーティングの作成
   - アクター
     - 運営（SO）
   - 概要
     - ミーティングを作成する
   - 利用ツール
     - Zoom
2. ミーティング情報の共有
   - アクター
     - 運営（SO）
   - 概要
     - ミーティング情報を共有する
   - 利用ツール
     - kintoneアプリ
3. ミーティング情報の確認
   - アクター
     - 講師
   - 概要
     - ミーティング情報を確認する
   - 利用ツール
     - kintoneアプリ
4. ミーティング情報の変更
   - アクター
     - 講師
   - 概要
     - ミーティングのアンケートや表示機能を変更する
   - 利用ツール
     - Zoom

---

## 2. ミーティングの起動と権限の設定

研修当日、講師がミーティングを起動し権限を設定する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["講師"]
        direction TB
        N1["1. ミーティングの起動<br/>Zoom"]:::instr
        N2["2. 共同ホスト権限の設定<br/>Zoom"]:::instr
        N1 --> N2
    end

    classDef instr fill:#4c7a5d,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1 lane;
```

### 作業

1. ミーティングの起動
   - アクター
     - 講師
   - 概要
     - ミーティング情報を基にミーティングを開始する
   - 利用ツール
     - Zoom
2. 共同ホスト権限の設定
   - アクター
     - 講師
   - 概要
     - 共同ホスト権限を設定する
   - 利用ツール
     - Zoom

---

## 3. ミーティングへの参加

受講生がミーティングに参加する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["受講生"]
        direction TB
        N1["1. ミーティングに参加<br/>Zoom"]:::student
    end
    subgraph G2["講師"]
        direction TB
        N2["2. 入室の許可<br/>Zoom"]:::instr
    end

    N1 --> N2

    classDef student fill:#a9822f,color:#000;
    classDef instr fill:#4c7a5d,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1,G2 lane;
```

### 作業

1. ミーティングに参加
   - アクター
     - 受講生
   - 概要
     - ミーティングに参加する
   - 利用ツール
     - Zoom
2. 入室の許可
   - アクター
     - 講師
   - 概要
     - 待機中の受講生の入室を許可する
   - 利用ツール
     - Zoom

---

## 4. ブレイクアウトルームの作成

講師がブレイクアウトルームを作成し受講生を割り当てる場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["講師"]
        direction TB
        N1["1. ブレイクアウトルームの作成<br/>Zoom"]:::instr
        N2["2. ブレイクアウトルームの割り当て<br/>Zoom"]:::instr
        N1 --> N2
    end

    classDef instr fill:#4c7a5d,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1 lane;
```

### 作業

1. ブレイクアウトルームの作成
   - アクター
     - 講師
   - 概要
     - ブレイクアウトルームを作成する
   - 利用ツール
     - Zoom
2. ブレイクアウトルームの割り当て
   - アクター
     - 講師
   - 概要
     - ブレイクアウトルームに受講生を割り当てる
   - 利用ツール
     - Zoom
