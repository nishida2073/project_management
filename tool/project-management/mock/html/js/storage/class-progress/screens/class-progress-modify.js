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
      MessageDialog.show('対象のクラスが見つかりません', function () { location.href = 'class_progress_list.html'; });
      return;
    }
    var classStart = new Date(cls.start);
    var courseInfo = ClassStore.COURSES[cls.courseCode];
    var projectInfo = ClassStore.PROJECTS[cls.projectCode];
    document.getElementById('subLine').textContent = (courseInfo ? courseInfo.name : cls.courseCode) + '　' + cls.lessonNo + '　' + cls.start + '〜' + cls.end;
    var tasks = TaskStore.load();
    var sortedTasks = tasks.slice().sort(function (a, b) {
      var ka = a.kinds[0] || '';
      var kb = b.kinds[0] || '';
      if (ka !== kb) return ka < kb ? -1 : 1;
      return a.order - b.order;
    });
    var displayNo = [];
    var kindCount = {};
    sortedTasks.forEach(function (t, i) {
      if (t.status === '停止中') return;
      var k = t.kinds[0] || '';
      kindCount[k] = (kindCount[k] || 0) + 1;
      displayNo[i] = kindCount[k];
    });
    var stepsList = sortedTasks.map(function (t, i) {
      return { no: i + 1, name: t.name, actual: '', owner: '', status: 'wait', memo: '' };
    });
    var saved = (loadProgress()[CLASS_KEY]) || {};
    var body = document.getElementById('stepBody');

    function ownerOptions(task) {
      var company = task ? task.company : StaffVenderStore.INTERNAL;
      var names = StaffStore.load().filter(function (s) {
        if (s.status === '停止中') return false;
        if (!(s.roles || []).some(function (code) { return StaffRoleStore.nameOf(code) === 'クラス'; })) return false;
        if (!(s.jobTypes || []).some(function (c) { return JobTypeStore.nameOf(c) === '実施'; })) return false;
        if (company === StaffVenderStore.INTERNAL) return s.affiliation === '社内';
        return s.affiliation === 'パートナー' && s.company === company;
      }).map(function (s) { return s.name; });
      return names;
    }

    function syncOwner(tr) {
      var on = !!ownText(tr.querySelector('.col-actual').querySelector('.js-date'));
      var sel = tr.querySelector('.col-owner').querySelector('.js-select');
      sel.style.opacity = on ? '' : '0.45';
      sel.style.pointerEvents = on ? '' : 'none';
    }

    stepsList.forEach(function (s, i) {
      var task = sortedTasks[i];
      if (task && (task.status === '停止中' || task.kinds.indexOf(cls.taskType) === -1)) return;
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
        '<td class="sticky" style="text-align: center;">' + displayNo[i] + '</td>' +
        '<td class="step-name sticky">' + esc(name) + '</td>' +
        '<td class="sticky"><div class="target-seg"><label class="target-opt"><input type="radio" name="target' + s.no + '" value="あり"' + (na ? '' : ' checked') + '><span>あり</span></label>' +
          '<label class="target-opt off"><input type="radio" name="target' + s.no + '" value="なし"' + (na ? ' checked' : '') + '><span>なし</span></label></div></td>' +
        '<td class="sticky" style="white-space: nowrap;">' + esc(company) + '</td>' +
        '<td>' + planCell + '</td>' +
        '<td class="col-actual">' + actualCell + '</td>' +
        '<td class="col-owner"><div class="mini-control wide js-select" data-options="' + ownerOptions(task).join(',') + '">' + esc(StaffStore.nameOf(owner)) + '<span class="caret">▾</span></div></td>' +
        '<td><div class="na-text"' + (na ? '' : ' style="display:none;"') + '>対象外</div><div class="status-select status-combo ' + STATUS_COLOR[status] + ' js-select"' + (na ? ' style="display:none;"' : '') + ' data-options="実施前,実施中,完了" data-class-map=\'{"実施前":"gray","実施中":"blue","完了":"green"}\'>' + STATUS_LABEL[status] + '<span class="caret">▾</span></div></td>' +
        '<td><textarea class="form-control textarea memo-area" rows="1">' + esc(memo) + '</textarea></td>';
      body.appendChild(tr);
      setDisabledRow(tr, na);
      syncOwner(tr);
      new MutationObserver(function () { syncOwner(tr); }).observe(tr.querySelector('.col-actual'), { childList: true, subtree: true, characterData: true });
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
          owner: ownText(tds[5].querySelector('.js-date')) ? StaffStore.codeOf(ownText(tds[6].querySelector('.js-select'))) : '',
          status: LABEL_STATUS[ownText(tds[7].querySelector('.js-select'))] || 'wait',
          memo: tds[8].querySelector('textarea').value
        };
      });
      all[CLASS_KEY] = Object.assign({}, all[CLASS_KEY] || {}, out);
      saveProgress(all);
      location.href = 'class_progress_list.html';
    });
  })();
