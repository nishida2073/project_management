(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function $(id) { return document.getElementById(id); }

  function init(opts) {
    var code = new URLSearchParams(location.search).get('id');
    var project = null;
    ProjectStore.load().forEach(function (p) { if (p.code === code) project = p; });
    if (!project) {
      alert('対象の案件が見つかりません');
      location.href = 'project_progress_list.html';
      return;
    }

    $('subLine').textContent = project.code + '　' + project.name + '　実施開始月：' + project.startMonth +
      '　管理担当者　' + StaffStore.nameOf(project.pm) + (project.pl && project.pl.length ? '／' + project.pl.map(function (c) { return StaffStore.nameOf(c); }).join('／') : '');

    var rec = ProjectProgressStore.find(project.code);
    var tbody = $('stepBody');
    ProjectProgressStore.STEP_NAMES.forEach(function (name, i) {
      var s = rec.steps[i] || ProjectProgressStore.blank(project.code).steps[i];
      var tr = document.createElement('tr');
      tr.setAttribute('data-index', i);
      tr.innerHTML =
        '<td class="step-name"><span class="step-no">' + (i + 1) + '</span>' + esc(name) + '</td>' +
        '<td><input type="text" class="form-control plan-input" value="' + esc(s.plan) + '" placeholder="2026/09/01" style="width:120px;"></td>' +
        '<td><input type="text" class="form-control actual-input" value="' + esc(s.actual) + '" placeholder="2026/09/01" style="width:120px;"></td>' +
        '<td><select class="form-control status-input">' +
          ['wait', 'progress', 'done'].map(function (v) {
            var label = { wait: '実施前', progress: '実施中', done: '完了' }[v];
            return '<option value="' + v + '"' + (s.status === v ? ' selected' : '') + '>' + label + '</option>';
          }).join('') +
        '</select></td>' +
        '<td style="text-align:center;"><input type="checkbox" class="target-input"' + (s.na ? '' : ' checked') + '></td>' +
        '<td><input type="text" class="form-control memo-input" value="' + esc(s.memo) + '"></td>';
      tbody.appendChild(tr);
    });

    $('saveBtn').addEventListener('click', function () {
      var steps = Array.prototype.map.call(tbody.querySelectorAll('tr'), function (tr) {
        return {
          status: tr.querySelector('.status-input').value,
          na: !tr.querySelector('.target-input').checked,
          plan: tr.querySelector('.plan-input').value.trim(),
          actual: tr.querySelector('.actual-input').value.trim(),
          memo: tr.querySelector('.memo-input').value
        };
      });
      ProjectProgressStore.upsert({ projectCode: project.code, steps: steps });
      location.href = 'project_progress_list.html';
    });
  }

  window.ProjectProgressEditor = { init: init };
})();
