  (function () {
    var body = document.getElementById('taskBody');
    var list = TaskStore.load();
    list.forEach(function (t) {
      var kinds = t.kinds.map(function (k) {
        return '<span class="tag ' + (TaskTypeStore.colorOf(k) || '') + '">' + esc(TaskTypeStore.nameOf(k)) + '</span>';
      }).join('');
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + esc(t.id) + '</td>' +
        '<td>' + esc(t.name) + '</td>' +
        '<td>' + kinds + '</td>' +
        '<td>' + (t.workType ? '<span class="tag ' + WorkTypeStore.colorOf(t.workType) + '">' + esc(WorkTypeStore.nameOf(t.workType)) + '</span>' : '') + '</td>' +
        '<td>' + esc(t.order) + '</td>' +
        '<td><span class="tag ' + (t.company === StaffVenderStore.INTERNAL ? 'blue' : 'orange') + '">' + (t.company === StaffVenderStore.INTERNAL ? '社内' : 'パートナー') + '</span></td>' +
        '<td>' + (t.company === StaffVenderStore.INTERNAL ? '' : esc(StaffVenderStore.nameOf(t.company))) + '</td>' +
        '<td>' + (t.days === '' || t.days === undefined ? '' : esc(t.days) + '日') + '</td>' +
        '<td><span class="badge overall-badge ' + (t.status === OperatingStatusStore.labelOf('STOPPED') ? 'gray' : 'green') + '">' + (t.status === OperatingStatusStore.labelOf('STOPPED') ? OperatingStatusStore.labelOf('STOPPED') : OperatingStatusStore.labelOf('ACTIVE')) + '</span></td>' +
      '<td class="memo-cell"' + (t.memo ? ' title="' + esc(t.memo) + '"' : '') + '>' + (t.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
        '<td class="row-actions"><a class="search-btn" href="task_modify.html?id=' + encodeURIComponent(t.id) + '">更新</a></td>';
      body.appendChild(tr);
    });
    document.getElementById('taskCount').textContent = list.length;
  })();
