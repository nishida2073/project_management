(function () {
  var KEY = 'courseList';

  function month(counts) {
    var m = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    counts.forEach(function (v) { m[v[0]] = v[1]; });
    return m;
  }

  function course(code, part, name, delivery, days, min, max, status, subject, actual, monthly) {
    return {
      code: code, year: '2026年度', subject: subject, part: part, name: name,
      delivery: delivery, days: days, min: min, max: max, status: status, actual: actual, monthly: monthly
    };
  }

  var SEED = [
    course('BC02B', 'PT-01', '受託_システム開発入門', 'DL-01', 3, 20, 24, '稼働中', 'BC02', 1, month([[5, 1], [9, 1]])),
    course('BC07A', 'PT-02', '公募_基盤技術基礎', 'DL-02', 1, 30, 40, '稼働中', 'BC07', 3, month([[0, 1], [1, 1], [2, 1], [3, 1]])),
    course('BC12B', 'PT-01', '受託_AP要件定義基礎', 'DL-01', 3, 20, 30, '稼働中', 'BC12', 2, month([[0, 1], [1, 1], [2, 1]])),
    course('BC17B', 'PT-01', '受託_AP設計・製造基礎', 'DL-01', 2, 15, 20, '停止中', 'BC17', 0, month([[0, 1], [1, 1]])),
    course('BC22B', 'PT-01', '受託_AP試験基礎', 'DL-01', 2, 20, 24, '稼働中', 'BC22', 2, month([[0, 1], [1, 1], [2, 1]])),
    course('BC27A', 'PT-02', '公募_データモデル設計基礎', 'DL-02', 1, 20, 30, '稼働中', 'BC27', 4, month([[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]])),
    course('BC32B', 'PT-01', '受託_基盤構築プロセス基礎', 'DL-01', 3, 15, 20, '稼働中', 'BC32', 1, month([[0, 1], [1, 1]])),
    course('DP08B', 'PT-01', '受託_営業基本Ⅰ', 'DL-01', 2, 20, 30, '稼働中', 'DP08', 2, month([[0, 1], [1, 1], [2, 1]])),
    course('DP16A', 'PT-02', '公募_営業リスクマネジメントⅠ', 'DL-02', 1, 25, 35, '稼働中', 'DP16', 3, month([[0, 1], [1, 1], [2, 1], [3, 1]])),
    course('GC01B', 'PT-01', '受託_IT-PM入門', 'DL-01', 2, 20, 24, '稼働中', 'GC01', 1, month([[0, 1], [1, 1]])),
    course('GC06B', 'PT-01', '受託_品質管理入門', 'DL-02', 1, 20, 30, '稼働中', 'GC06', 3, month([[0, 1], [1, 1], [2, 1], [3, 1]])),
    course('ND02B', 'PT-01', '受託_AP要件定義基礎', 'DL-01', 3, 20, 30, '稼働中', 'BC12', 1, month([[0, 1], [1, 1]])),
    course('CE01B', 'PT-01', '受託_AP設計・製造基礎', 'DL-01', 2, 15, 20, '稼働中', 'BC17', 1, month([[0, 1], [1, 1]])),
    course('BE10A', 'PT-02', '公募_システム基盤実践', 'DL-01', 3, 15, 20, '稼働中', 'BE10', 1, month([[0, 1], [1, 1]])),
    course('BC022A', 'PT-02', '公募_システム開発入門', 'DL-01', 2, 15, 25, '稼働中', 'BC02', 0, month([])),
    course('BC022B', 'PT-01', '受託_システム開発入門', 'DL-01', 2, 15, 25, '稼働中', 'BC02', 0, month([])),
    course('BC072A', 'PT-02', '公募_基盤技術基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC07', 0, month([])),
    course('BC072B', 'PT-01', '受託_基盤技術基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC07', 0, month([])),
    course('BC122A', 'PT-02', '公募_AP要件定義基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC12', 0, month([])),
    course('BC122B', 'PT-01', '受託_AP要件定義基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC12', 0, month([])),
    course('BC172A', 'PT-02', '公募_AP設計製造基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC17', 0, month([])),
    course('BC172B', 'PT-01', '受託_AP設計製造基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC17', 0, month([])),
    course('BC222A', 'PT-02', '公募_AP試験基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC22', 0, month([])),
    course('BC222B', 'PT-01', '受託_AP試験基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC22', 0, month([])),
    course('BC272A', 'PT-02', '公募_データモデル設計基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC27', 0, month([])),
    course('BC272B', 'PT-01', '受託_データモデル設計基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC27', 0, month([])),
    course('BC322A', 'PT-02', '公募_基盤構築プロセス基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC32', 0, month([])),
    course('BC322B', 'PT-01', '受託_基盤構築プロセス基礎', 'DL-01', 2, 15, 25, '稼働中', 'BC32', 0, month([])),
    course('BD111A', 'PT-02', '外販公募_システム開発基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD11', 0, month([])),
    course('BD112B', 'PT-01', '外販受託_システム開発基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD11', 0, month([])),
    course('BD121A', 'PT-02', '外販公募_基盤技術基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD12', 0, month([])),
    course('BD122B', 'PT-01', '外販受託_基盤技術基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD12', 0, month([])),
    course('BD131A', 'PT-02', '外販公募_要件定義基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD13', 0, month([])),
    course('BD132B', 'PT-01', '外販受託_要件定義基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD13', 0, month([])),
    course('BD141A', 'PT-02', '外販公募_ソフトウェア設計基礎（アプリケーション設計・製造基礎）', 'DL-01', 2, 15, 25, '稼働中', 'BD14', 0, month([])),
    course('BD142B', 'PT-01', '外販受託_ソフトウェア設計基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD14', 0, month([])),
    course('BD151A', 'PT-02', '外販公募_データモデル設計基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD15', 0, month([])),
    course('BD152B', 'PT-01', '外販受託_データモデル設計基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD15', 0, month([])),
    course('BD161A', 'PT-02', '外販公募_ソフトウェア試験基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD16', 0, month([])),
    course('BD162B', 'PT-01', '外販受託_ソフトウェア試験基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD16', 0, month([])),
    course('BD171A', 'PT-02', '外販公募_品質管理基礎（品質管理入門）', 'DL-01', 2, 15, 25, '稼働中', 'BD17', 0, month([])),
    course('BD172B', 'PT-01', '外販受託_品質管理基礎', 'DL-01', 2, 15, 25, '稼働中', 'BD17', 0, month([])),
    course('BD181A', 'PT-02', '外販公募_プロジェクトマネジメント基礎（ITPM入門）', 'DL-01', 2, 15, 25, '稼働中', 'BD18', 0, month([])),
    course('BD182B', 'PT-01', '外販受託_プロジェクトマネジメント基礎（ITPM入門）', 'DL-01', 2, 15, 25, '稼働中', 'BD18', 0, month([])),
    course('AA6B', 'PT-01', 'フォローアップ研修', 'DL-01', 2, 15, 25, '稼働中', 'AA60', 0, month([]))
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED));
    save(seed);
    return seed;
  }

  function planned(c) {
    return (c.monthly || []).reduce(function (a, b) { return a + (parseInt(b, 10) || 0); }, 0);
  }

  function map() {
    var out = {};
    load().forEach(function (c) {
      out[c.code] = {
        name: c.name,
        part: c.part,
        delivery: c.delivery,
        schedule: c.days + '日・' + c.min + '〜' + c.max + '名'
      };
    });
    return out;
  }

  window.CourseStore = {
    load: load,
    save: save,
    planned: planned,
    map: map
  };
})();
