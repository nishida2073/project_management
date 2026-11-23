(function () {
  var loginJobs = JSON.parse(sessionStorage.getItem('loginJobNames') || '[]');
  var lockOn = sessionStorage.getItem('loginUserCode') !== null && sessionStorage.getItem('loginIsAdmin') !== '1' && loginJobs.indexOf('管理') === -1;
  var STATUS_LABEL = StepStatusStore.nameByCode();
  var LABEL_STATUS = StepStatusStore.byName();
  var STATUS_COLOR = { DONE: 'green', PROGRESS: 'blue', WAIT: 'gray' };

function setDisabledRow(tr, off) {
  Array.prototype.forEach.call(tr.querySelectorAll('.js-date, .status-input'), function (el) {
    el.style.pointerEvents = off ? 'none' : '';
    el.style.opacity = off ? '0.4' : '';
  });
}

  var PROJECT_CODE = new URLSearchParams(location.search).get('id') || '';
  var project = null;
  ProjectStore.load().forEach(function (p) { if (p.code === PROJECT_CODE) project = p; });
  if (!project) {
    MessageDialog.show('対象の案件が見つかりません', function () { location.href = 'project_progress_list.html'; });
      } else {
    $('subLine').textContent = project.code + '　' + project.name + '　実施開始月：' + project.startMonth +
      '　管理担当者：' + StaffStore.nameOf(project.pm) + (project.pl && project.pl.length ? '／' + project.pl.map(function (c) { return StaffStore.nameOf(c); }).join('／') : '');

    var rec = ProjectProgressStore.find(project.code);
    var blank = ProjectProgressStore.blank(project.code).steps;
    var body = $('stepBody');

    var ownerNames = StaffStore.candidates({ affiliations: [AffiliationStore.nameOf('INTERNAL')], roles: ['案件'], jobTypes: ['実施'] });
    ProjectProgressStore.STEP_NAMES.forEach(function (name, i) {
      var s = rec.steps[i] || blank[i];
      var tr = document.createElement('tr');
      tr.setAttribute('data-no', i + 1);
      tr.innerHTML =
        '<td class="sticky" style="text-align: center;">' + (i + 1) + '</td>' +
        '<td class="step-name sticky">' + esc(name) + '</td>' +
        '<td><div class="target-seg"><label class="target-opt"><input type="radio" name="target' + i + '" value="あり"' + (s.na ? '' : ' checked') + '><span>あり</span></label>' +
          '<label class="target-opt off"><input type="radio" name="target' + i + '" value="なし"' + (s.na ? ' checked' : '') + '><span>なし</span></label></div></td>' +
        '<td><div class="mini-control js-date plan-input" data-no-closed-day>' + esc(s.plan || '') + '<span class="caret">▾</span></div></td>' +
        '<td><div class="mini-control js-date actual-input" data-no-closed-day>' + esc(s.actual || '') + '<span class="caret">▾</span></div></td>' +
        '<td><div class="mini-control wide js-select owner-input" data-options="' + esc(ownerNames.join(',')) + '">' + esc(StaffStore.nameOf(s.owner || '') || '選択してください') + '<span class="caret">▾</span></div></td>' +
        '<td>' +
          '<div class="status-select status-combo ' + STATUS_COLOR[s.status] + ' js-select status-input"' + ' data-options="' + StepStatusStore.options() + '" data-class-map=\'' + StepStatusStore.classMapJson() + '\'>' + STATUS_LABEL[s.status] + '<span class="caret">▾</span></div></td>' +
        '<td><textarea class="form-control textarea memo-area" rows="1">' + esc(s.memo) + '</textarea></td>';
      body.appendChild(tr);
      if (lockOn) {
        Array.prototype.forEach.call(tr.querySelectorAll('input[type="radio"]'), function (r) { r.disabled = true; });
        tr.children[2].classList.add('is-locked');
        tr.children[3].classList.add('is-locked');
      }
      setDisabledRow(tr, s.na);
      Array.prototype.forEach.call(tr.querySelectorAll('input[type="radio"]'), function (r) {
        r.addEventListener('change', function () {
          var na = r.value === 'なし';
          setDisabledRow(tr, na);
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
          owner: StaffStore.codeOf(ownText(tds[5].querySelector('.js-select'))),
          status: LABEL_STATUS[ownText(tds[6].querySelector('.js-select'))] || 'WAIT',
          memo: tds[7].querySelector('textarea').value
        });
      });
      ProjectProgressStore.upsert({ projectCode: project.code, steps: out });
      location.href = 'project_progress_list.html';
    });
  }
})();
