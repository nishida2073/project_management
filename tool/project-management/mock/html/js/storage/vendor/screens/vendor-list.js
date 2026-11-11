(function () {
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  var body = document.getElementById('vendorBody');
  var list = VendorStore.load();

  list.forEach(function (v) {
    var on = v.status !== '停止中';
    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td>' + esc(v.code) + '</td>' +
      '<td>' + esc(v.name) + '</td>' +
      '<td><span class="tag ' + (ContractTypeStore.colorOf(v.contract) || 'blue') + '">' + esc(ContractTypeStore.nameOf(v.contract)) + '</span></td>' +
      '<td>' + (v.years || []).map(function (y) { return '<span class="chip y' + y.replace(/[^0-9]/g, '') + '">' + esc(y) + '</span>'; }).join(' ') + '</td>' +
      '<td>' + esc(v.tel) + '</td>' +
      '<td>' + esc(v.memo) + '</td>' +
      '<td>' + esc(v.contactName) + '</td>' +
      '<td><span class="state ' + (on ? 'on' : 'off') + '"><span class="dot"></span>' + (on ? '稼働中' : '停止中') + '</span></td>' +
      '<td><a class="search-btn" href="vendor_modify.html?id=' + encodeURIComponent(v.code) + '">編集</a></td>';
    body.appendChild(tr);
  });

  document.getElementById('vendorCount').textContent = list.length;
})();
