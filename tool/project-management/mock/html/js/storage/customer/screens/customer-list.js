(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  var body = document.getElementById('customerBody');
  var list = CustomerStore.load();

  list.forEach(function (c) {
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(c.id) + '</td>' +
      '<td>' + esc(c.name) + '</td>' +
      '<td>' + esc(c.staff || '-') + '</td>' +
      '<td class="row-actions"><a class="search-btn" href="customer_modify.html?id=' + encodeURIComponent(c.id) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('customerCount').textContent = list.length;
})();
