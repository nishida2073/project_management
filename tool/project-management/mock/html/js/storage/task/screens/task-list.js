  (function () {
    function esc(s) {
      return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    var body = document.getElementById('taskBody');
    var list = TaskStore.load();
    list.forEach(function (t) {
      var kinds = t.kinds.map(function (k) {
        return '<span class="tag ' + (TaskKindStore.colorOf(k) || '') + '">' + esc(TaskKindStore.nameOf(k)) + '</span>';
      }).join('');
      var tr = document.createElement('tr');
      tr.innerHTML =
        '<td>' + esc(t.id) + '</td>' +
        '<td>' + esc(t.name) + '</td>' +
        '<td>' + kinds + '</td>' +
        '<td>' + esc(t.order) + '</td>' +
        '<td>' + esc(VendorStore.nameOf(t.company)) + '</td>' +
        '<td>' + esc(t.days) + '</td>' +
        '<td><a class="search-btn" href="task_modify.html?id=' + encodeURIComponent(t.id) + '">編集</a></td>';
      body.appendChild(tr);
    });
    document.getElementById('taskCount').textContent = list.length;
  })();
