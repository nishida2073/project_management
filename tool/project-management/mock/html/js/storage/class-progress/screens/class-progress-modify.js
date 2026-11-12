  (function () {
    var CLASS_ID = new URLSearchParams(location.search).get('id') || 'CLS-001';
    var CLASS_KEY = CLASS_ID;
    var STATUS_LABEL = { done: '完了', progress: '実施中', wait: '実施前' };
    var LABEL_STATUS = { '完了': 'done', '実施中': 'progress', '実施前': 'wait' };
    var STATUS_COLOR = { done: 'green', progress: 'blue', wait: 'gray' };

function setDisabledRow(tr, off) {
  Array.prototype.forEach.call(tr.querySelectorAll('.js-date, .wide.js-select'), function (el) {
    el.style.pointerEvents = off ? 'none' : '';
    el.style.opacity = off ? '0.4' : '';
  });
}
    var STEPS = [
      { no: 1, name: 'クラス登録', actual: '2026/08/20', owner: 'STF-045', status: 'done', memo: '' },
      { no: 2, name: '名簿受領督促', actual: '2026/08/25', owner: '', status: 'done', memo: '' },
      { no: 3, name: '講師契約', actual: '2026/08/27', owner: 'STF-045', status: 'done', memo: '' },
      { no: 4, name: '受講者登録(OliveOne)', actual: '', owner: '', status: 'progress', memo: '' },
      { no: 5, name: '受講詳細案内発出', actual: '2026/08/31', owner: 'STF-045', status: 'done', memo: '' },
      { no: 6, name: '電子教材送付', actual: '', owner: '', status: 'progress', memo: '2名分の宛先要再確認' },
      { no: 7, name: '出欠確認・報告', actual: '', owner: 'STF-045', status: 'wait', memo: '11時までに送信' },
      { no: 8, name: 'アンケート実施案内', actual: '', owner: '', status: 'wait', memo: '' },
      { no: 9, name: 'テスト結果集計', actual: '', owner: '', status: 'wait', memo: '' },
      { no: 10, name: 'アンケート集計・格納', actual: '', owner: '', status: 'wait', memo: '' },
      { no: 11, name: '報告書作成', actual: '', owner: 'STF-045', status: 'wait', memo: '' },
      { no: 12, name: '再テストリマインド', actual: '', owner: '', status: 'wait', memo: '' }
    ];

    function esc(s) {
      return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    function addDays(days) {
      var d = new Date(classStart);
      d.setDate(d.getDate() + days);
      return d.getFullYear() + '/' + pad(d.getMonth() + 1) + '/' + pad(d.getDate());
    }
    function loadProgress() { return ProgressStore.load(); }
    function saveProgress(all) { ProgressStore.save(all); }
    function ownText(el) {
      return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
        .map(function (n) { return n.textContent; }).join('').trim();
    }

    var classList = ClassStore.load();
    var cls = null;
    classList.forEach(function (r) { if (r.id === CLASS_ID) cls = r; });
    if (!cls) {
      alert('対象のクラスが見つかりません');
      location.href = 'class_progress_list.html';
      return;
    }
    var classStart = new Date(cls.start);
    var courseInfo = ClassStore.COURSES[cls.courseCode];
    var projectInfo = ClassStore.PROJECTS[cls.projectCode];
    document.getElementById('subLine').textContent = cls.lessonNo + '　' + (courseInfo ? courseInfo.name : cls.courseCode) + '　' + cls.start + '〜' + cls.end + '　管理担当者：' + StaffStore.nameOf(cls.manager);
    var tasks = TaskStore.load();
    var sortedTasks = tasks.slice().sort(function (a, b) { return a.order - b.order; });
    var saved = (loadProgress()[CLASS_KEY]) || {};
    var body = document.getElementById('stepBody');

    function ownerOptions(task) {
      var company = task ? task.company : StaffVenderStore.INTERNAL;
      var names = StaffStore.load().filter(function (s) {
        if (s.status === '停止中') return false;
        if (company === StaffVenderStore.INTERNAL) return s.affiliation === '社内';
        return s.affiliation === 'パートナー' && s.company === company;
      }).map(function (s) { return s.name; });
      return names;
    }

    STEPS.forEach(function (s, i) {
      var task = sortedTasks[i];
      var name = task ? task.name : s.name;
      var sv = saved[s.no] || {};
      var plan = sv.plan !== undefined ? sv.plan : (task ? addDays(task.days) : '');
      var actual = sv.actual !== undefined ? sv.actual : s.actual;
      var owner = sv.owner !== undefined ? sv.owner : s.owner;
      var status = sv.status !== undefined ? sv.status : s.status;
      var memo = sv.memo !== undefined ? sv.memo : s.memo;
      var na = sv.na !== undefined ? sv.na : false;
      var company = task ? StaffVenderStore.nameOf(task.company) : '-';

      var planCell = plan
        ? '<div class="mini-control js-date">' + esc(plan) + '<span class="caret">▾</span></div>'
        : '<div class="mini-control js-date"><span class="caret">▾</span></div>';
      var actualCell = actual
        ? '<div class="mini-control js-date">' + esc(actual) + '<span class="caret">▾</span></div>'
        : '<div class="mini-control js-date"><span class="caret">▾</span></div>';

      var tr = document.createElement('tr');
      tr.setAttribute('data-no', s.no);
      tr.innerHTML =
        '<td class="sticky" style="text-align: center; font-weight: 700;">' + s.no + '</td>' +
        '<td class="step-name sticky">' + esc(name) + '</td>' +
        '<td><label class="radio-option"><input type="radio" name="target' + s.no + '" value="あり"' + (na ? '' : ' checked') + '><span class="radio-dot"></span><span>あり</span></label>' +
          '<label class="radio-option"><input type="radio" name="target' + s.no + '" value="なし"' + (na ? ' checked' : '') + '><span class="radio-dot"></span><span>なし</span></label></td>' +
        '<td style="white-space: nowrap; font-weight: 700;">' + esc(company) + '</td>' +
        '<td>' + planCell + '</td>' +
        '<td>' + actualCell + '</td>' +
        '<td><div class="mini-control wide js-select" data-options="' + ownerOptions(task).join(',') + '">' + esc(StaffStore.nameOf(owner)) + '<span class="caret">▾</span></div></td>' +
        '<td><div class="na-text"' + (na ? '' : ' style="display:none;"') + '>対象外</div><div class="status-select ' + STATUS_COLOR[status] + ' js-select"' + (na ? ' style="display:none;"' : '') + ' data-options="実施前,実施中,完了" data-class-map=\'{"実施前":"gray","実施中":"blue","完了":"green"}\'>' + STATUS_LABEL[status] + '<span class="caret">▾</span></div></td>' +
        '<td><input type="text" class="memo-input" value="' + esc(memo) + '"></td>';
      body.appendChild(tr);
      setDisabledRow(tr, na);
      Array.prototype.forEach.call(tr.querySelectorAll('input[type="radio"]'), function (r) {
        r.addEventListener('change', function () {
          var off = r.value === 'なし';
          setDisabledRow(tr, off);
          tr.querySelector('.na-text').style.display = off ? '' : 'none';
          tr.querySelector('.status-select').style.display = off ? 'none' : '';
        });
      });
    });

    document.getElementById('saveBtn').addEventListener('click', function () {
      var all = loadProgress();
      var out = {};
      Array.prototype.forEach.call(body.querySelectorAll('tr'), function (tr) {
        var no = tr.getAttribute('data-no');
        var tds = tr.children;
        out[no] = {
          na: tr.querySelector('input[type="radio"]:checked').value === 'なし',
          plan: ownText(tds[4].querySelector('.js-date')),
          actual: ownText(tds[5].querySelector('.js-date')),
          owner: StaffStore.codeOf(ownText(tds[6].querySelector('.js-select'))),
          status: LABEL_STATUS[ownText(tds[7].querySelector('.js-select'))] || 'wait',
          memo: tds[8].querySelector('input').value
        };
      });
      all[CLASS_KEY] = out;
      saveProgress(all);
      location.href = 'class_progress_list.html';
    });
  })();
