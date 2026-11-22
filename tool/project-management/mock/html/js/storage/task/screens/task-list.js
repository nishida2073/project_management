  (function () {
    var body = document.getElementById('taskBody');
    var list = TaskStore.load();
    list.forEach(function (t) {
      var kinds = t.kinds.map(function (k) {
        return '<span class="tag task-type-tag ' + (TaskTypeStore.colorOf(k) || '') + '">' + esc(TaskTypeStore.nameOf(k)) + '</span>';
      }).join('');
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + esc(t.id) + '</td>' +
        '<td>' + esc(t.name) + '</td>' +
        '<td><div class="tag-stack">' + kinds + '</div></td>' +
        '<td>' + (t.workType ? '<span class="tag work-type-tag ' + WorkTypeStore.colorOf(t.workType) + '">' + esc(WorkTypeStore.nameOf(t.workType)) + '</span>' : '') + '</td>' +
        '<td>' + esc(t.order) + '</td>' +
        '<td><span class="tag affiliation-tag ' + (t.company === StaffVenderStore.INTERNAL ? 'blue' : 'orange') + '">' + (t.company === StaffVenderStore.INTERNAL ? AffiliationStore.nameOf('INTERNAL') : AffiliationStore.nameOf('PARTNER')) + '</span></td>' +
        '<td>' + (t.company === StaffVenderStore.INTERNAL ? '' : esc(StaffVenderStore.nameOf(t.company))) + '</td>' +
        '<td>' + (t.days === '' || t.days === undefined ? '' : esc(t.days) + '日') + '</td>' +
        '<td><span class="status-label ' + (t.status === OperatingStatusStore.nameOf('STOPPED') ? 'gray' : 'green') + '">' + (t.status === OperatingStatusStore.nameOf('STOPPED') ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE')) + '</span></td>' +
      '<td class="memo-cell"' + (t.memo ? ' data-memo="' + esc(t.memo) + '"' : '') + '>' + (t.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
        '<td class="row-actions"><a class="nav-btn" href="task_modify.html?id=' + encodeURIComponent(t.id) + '">更新</a></td>';
      body.appendChild(tr);
    });
    document.getElementById('taskCount').textContent = list.length;
  })();

(function () {
  var INTERNAL_NAME = AffiliationStore.nameOf('INTERNAL');
  var SHEET_SPEC = {
    sheetName: 'タスク',
    load: function () { return TaskStore.load(); },
    columns: [
      { key: 'id', label: 'コード', type: 'text', required: false },
      { key: 'name', label: '名称', type: 'text', required: true },
      { key: 'kinds', label: 'タスク区分', type: 'text', required: true,
        format: function (r) { return (r.kinds || []).map(function (c) { return TaskTypeStore.nameOf(c); }).join(','); },
        parse: function (t) { return t.split(',').map(function (x) { return x.trim(); }).filter(Boolean).map(function (n) { return StoreImport.codeByName(TaskTypeStore, n); }).filter(Boolean); } },
      { key: 'order', label: '順番', type: 'text', required: true, format: function (r) { return r.order === undefined ? '' : r.order; }, parse: StoreImport.numOf },
      { key: 'affiliation', label: '実務担当区分', type: 'select', required: true, options: AffiliationStore.load().map(function (a) { return a.name; }),
        format: function (r) { return r.company === StaffVenderStore.INTERNAL ? INTERNAL_NAME : AffiliationStore.nameOf('PARTNER'); },
        parse: function (t) { return t; } },
      { key: 'companyName', label: '所属先', type: 'text', required: false,
        format: function (r) { return r.company === StaffVenderStore.INTERNAL ? '' : StaffVenderStore.nameOf(r.company); },
        parse: function (t) { return t; } },
      { key: 'days', label: '予定開始日数', type: 'text', required: true, format: function (r) { return r.days === undefined ? '' : r.days; }, parse: StoreImport.numOf },
      { key: 'workType', label: '作業区分', type: 'text', required: true,
        format: function (r) { return WorkTypeStore.nameOf(r.workType); },
        parse: function (t) { return StoreImport.codeByName(WorkTypeStore, t); } },
      { key: 'memo', label: '備考', type: 'text', required: false, format: function (r) { return r.memo || ''; } },
      { key: 'status', label: '稼働状態', type: 'select', required: true, options: [OperatingStatusStore.nameOf('ACTIVE'), OperatingStatusStore.nameOf('STOPPED')] }
    ],
    existingKeys: function () { return TaskStore.load().map(function (t) { return t.id; }); },
    keyOf: function (o) { return o.id; },
    add: function (o) {
      var list = TaskStore.load();
      list.push(taskRecord(o, o.id || TaskStore.nextId(list)));
      TaskStore.save(list);
    },
    update: function (o) {
      var list = TaskStore.load();
      list.forEach(function (t) {
        if (t.id === o.id) {
          var rec = taskRecord(o, t.id);
          for (var k in rec) { t[k] = rec[k]; }
        }
      });
      TaskStore.save(list);
    },
    refresh: function () { location.reload(); }
  };
  function taskRecord(o, id) {
    var internal = o.affiliation === INTERNAL_NAME;
    return { id: id, name: o.name, kinds: o.kinds, order: o.order,
      company: internal ? StaffVenderStore.INTERNAL : StaffVenderStore.codeOf(o.companyName),
      days: o.days, workType: o.workType, memo: o.memo, status: o.status };
  }
  StoreImport.bind(SHEET_SPEC, { export: 'taskExport', import: 'taskImport', file: 'taskImportFile', fileName: 'タスク.xlsx' });
})();
