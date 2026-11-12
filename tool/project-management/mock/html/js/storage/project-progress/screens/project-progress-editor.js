(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }
  function ownText(el) {
    return Array.prototype.filter.call(el.childNodes, function (n) { return n.nodeType === 3; })
      .map(function (n) { return n.textContent; }).join('').trim();
  }
  var STATUS_LABEL = { done: '完了', progress: '実施中', wait: '実施前' };
  var LABEL_STATUS = { '完了': 'done', '実施中': 'progress', '実施前': 'wait' };
  var STATUS_COLOR = { done: 'green', progress: 'blue', wait: 'gray' };

function setDisabledRow(tr, off) {
  Array.prototype.forEach.call(tr.querySelectorAll('.js-date'), function (el) {
    el.style.pointerEvents = off ? 'none' : '';
    el.style.opacity = off ? '0.4' : '';
  });
}

  var PROJECT_CODE = new URLSearchParams(location.search).get('id') || '';
  var project = null;
  ProjectStore.load().forEach(function (p) { if (p.code === PROJECT_CODE) project = p; });
  if (!project) {
    alert('対象の案件が見つかりません');
    location.href = 'project_progress_list.html';
  } else {
    $('subLine').textContent = project.code + '　' + project.name + '　実施開始月：' + project.startMonth +
      '　管理担当者　' + StaffStore.nameOf(project.pm) + (project.pl && project.pl.length ? '／' + project.pl.map(function (c) { return StaffStore.nameOf(c); }).join('／') : '');

    var rec = ProjectProgressStore.find(project.code);
    var blank = ProjectProgressStore.blank(project.code).steps;
    var body = $('stepBody');

    ProjectProgressStore.STEP_NAMES.forEach(function (name, i) {
      var s = rec.steps[i] || blank[i];
      var tr = document.createElement('tr');
      tr.setAttribute('data-no', i + 1);
      tr.innerHTML =
        '<td class="sticky" style="text-align: center; font-weight: 700;">' + (i + 1) + '</td>' +
        '<td class="step-name sticky">' + esc(name) + '</td>' +
        '<td><div class="target-seg"><label class="target-opt"><input type="radio" name="target' + i + '" value="あり"' + (s.na ? '' : ' checked') + '><span>あり</span></label>' +
          '<label class="target-opt off"><input type="radio" name="target' + i + '" value="なし"' + (s.na ? ' checked' : '') + '><span>なし</span></label></div></td>' +
        '<td><div class="mini-control js-date plan-input">' + esc(s.plan || '') + '<span class="caret">▾</span></div></td>' +
        '<td><div class="mini-control js-date actual-input">' + esc(s.actual || '') + '<span class="caret">▾</span></div></td>' +
        '<td><div class="na-text"' + (s.na ? '' : ' style="display:none;"') + '>対象外</div>' +
          '<div class="status-select ' + STATUS_COLOR[s.status] + ' js-select status-input"' + (s.na ? ' style="display:none;"' : '') + ' data-options="実施前,実施中,完了" data-class-map=\'{"実施前":"gray","実施中":"blue","完了":"green"}\'>' + STATUS_LABEL[s.status] + '<span class="caret">▾</span></div></td>' +
        '<td><input type="text" class="memo-input" value="' + esc(s.memo) + '"></td>';
      body.appendChild(tr);
      setDisabledRow(tr, s.na);
      Array.prototype.forEach.call(tr.querySelectorAll('input[type="radio"]'), function (r) {
        r.addEventListener('change', function () {
          var na = r.value === 'なし';
          setDisabledRow(tr, na);
          tr.querySelector('.na-text').style.display = na ? '' : 'none';
          tr.querySelector('.status-input').style.display = na ? 'none' : '';
        });
      });
    });

    $('saveBtn').addEventListener('click', function () {
      var out = [];
      Array.prototype.forEach.call(body.querySelectorAll('tr'), function (tr) {
        var tds = tr.children;
        out.push({
          na: tr.querySelector('input[type="radio"]:checked').value === 'なし',
          plan: ownText(tds[3].querySelector('.js-date')),
          actual: ownText(tds[4].querySelector('.js-date')),
          status: LABEL_STATUS[ownText(tds[5].querySelector('.js-select'))] || 'wait',
          memo: tds[6].querySelector('input').value
        });
      });
      ProjectProgressStore.upsert({ projectCode: project.code, steps: out });
      location.href = 'project_progress_list.html';
    });
  }
})();
