(function () {

  var body = document.getElementById('customerBody');
  var list = CustomerStore.load();

  list.forEach(function (c) {
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.id) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + dashOr(c.staff) + '</td>' +
      '<td>' + dashOr(c.email) + '</td>' +
      '<td><span class="status-label ' + (c.status === OperatingStatusStore.nameOf('STOPPED') ? 'gray' : 'green') + '">' + (c.status === OperatingStatusStore.nameOf('STOPPED') ? OperatingStatusStore.nameOf('STOPPED') : OperatingStatusStore.nameOf('ACTIVE')) + '</span></td>' +
      '<td class="memo-cell"' + (c.memo ? ' data-memo="' + esc(c.memo) + '"' : '') + '>' + (c.memo ? '<span class="memo-mark">!</span>' : '') + '</td>' +
      '<td class="row-actions"><a class="nav-btn" href="customer_modify.html?id=' + encodeURIComponent(c.id) + '">更新</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('customerCount').textContent = list.length;
})();
