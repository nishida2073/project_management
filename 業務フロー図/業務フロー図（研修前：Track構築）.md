# Track構築フロー

## 概要

Track環境の構築用資材の準備から、クラス環境・アカウントの構築までの一連の業務フローです。

- 構築用資材の準備
- 環境の構築（クラス）
- 環境の構築（アカウント）

各業務は、発生タイミングや条件ごとに複数の図に分割し、担当者（レーン）ごとの流れを示しています。

### 実施タイミング

- 研修前

**凡例**

- レーン（枠）：運営（SO）（紫）／運営（SD）（ワイン）／構築担当者（テイール）
- 各業務は、発生タイミングや条件ごとに複数の図に分けています。各見出し直下の説明文が、その図が発生する条件です。
- 黄色い点線枠：元資料の注記（補足事項）

---

## 1. 構築用資材の準備

新年度・新規開催に向けて、Track構築用資材を準備する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["運営（SD）"]
        direction TB
        N1["1. マスターの共有<br/>Track"]:::sd
    end
    subgraph G2["運営（SO）"]
        direction TB
        N2["2. マスターの確認<br/>Track"]:::so
        N3["3. 構築対象一覧の作成<br/>Excel"]:::so
        N4["4. 構築用資材の共有<br/>Teams"]:::so
        N2 --> N3 --> N4
    end

    N1 --> N2

    classDef sd fill:#8a4c6b,color:#000;
    classDef so fill:#6b5b8a,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1,G2 lane;
```

### 作業

1. マスターの共有
   - アクター
     - 運営（SD）
   - 概要
     - マスターを共有する
   - 利用ツール
     - Track
2. マスターの確認
   - アクター
     - 運営（SO）
   - 概要
     - マスターを確認する
   - 利用ツール
     - Track
3. 構築対象一覧の作成
   - アクター
     - 運営（SO）
   - 概要
     - 構築が必要なクラスを一覧にまとめる
   - 利用ツール
     - Excel
4. 構築用資材の共有
   - アクター
     - 運営（SO）
   - 概要
     - マスター、構築対象一覧を構築担当者に共有する
   - 利用ツール
     - Teams

---

## 2. 環境の構築（クラス）

構築用資材の共有後、構築担当者がクラス環境を構築し、運営（SO）が確認する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["構築担当者"]
        direction TB
        N1["1. マスターの確認<br/>Track"]:::build
        N2["2. 構築対象一覧の確認<br/>Excel"]:::build
        N3["3. 環境の作成<br/>Track"]:::build
        N4["4. 環境の共有<br/>Teams"]:::build
        N1 --> N2 --> N3 --> N4
    end
    subgraph G2["運営（SO）"]
        direction TB
        N5["5. 環境の確認<br/>Track"]:::so
    end

    N4 --> N5

    classDef build fill:#4c8a8a,color:#000;
    classDef so fill:#6b5b8a,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1,G2 lane;
```

### 作業

1. マスターの確認
   - アクター
     - 構築担当者
   - 概要
     - マスターの内容を確認する
   - 利用ツール
     - Track
2. 構築対象一覧の確認
   - アクター
     - 構築担当者
   - 概要
     - 構築が必要なクラスを確認する
   - 利用ツール
     - Excel
3. 環境の作成
   - アクター
     - 構築担当者
   - 概要
     - マスターを基に、クラスを作成する
   - 利用ツール
     - Track
4. 環境の共有
   - アクター
     - 構築担当者
   - 概要
     - 構築した環境を共有する
   - 利用ツール
     - Teams
5. 環境の確認
   - アクター
     - 運営（SO）
   - 概要
     - クラスが正しく作成されていることを確認する
   - 利用ツール
     - Track

---

## 3. 環境の構築（アカウント）

クラス環境の構築後、運営（SO）がアカウントを構築する場合の流れです。

### フロー図
```mermaid
flowchart LR
    subgraph G1["運営（SO）"]
        direction TB
        N1["1. アカウント一覧の作成<br/>Excel"]:::so
        N2["2. アカウントの作成<br/>Track"]:::so
        N1 --> N2
    end

    classDef so fill:#6b5b8a,color:#000;
    classDef note fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c;
    classDef lane fill:#f2f2f2,stroke:#b0b0b0,color:#000;
    classDef invisible fill:none,stroke:none;

    class G1 lane;
```

### 作業

1. アカウント一覧の作成
   - アクター
     - 運営（SO）
   - 概要
     - 構築が必要なアカウントの一覧をまとめる
   - 利用ツール
     - Excel
2. アカウントの作成
   - アクター
     - 運営（SO）
   - 概要
     - アカウントを作成（クラスとの紐づけなど）する
   - 利用ツール
     - Track
