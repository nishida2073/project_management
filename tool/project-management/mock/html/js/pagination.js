(function () {
  var PER = 100;
  var state = { page: 1 };

  function init() {
    var card = document.querySelector('.table-card');
    var table = card && card.querySelector('table');
    var tbody = table && table.querySelector('tbody');
    var pag = card && card.querySelector('.pagination');
    if (!tbody || !pag) return;

    function rowsAll() {
      return Array.prototype.slice.call(tbody.querySelectorAll('tr'));
    }

    function rowsMatched() {
      return rowsAll().filter(function (tr) { return tr.getAttribute('data-match') !== '0'; });
    }

    function render() {
      var matched = rowsMatched();
      var pages = Math.max(1, Math.ceil(matched.length / PER));
      if (state.page > pages) state.page = pages;
      matched.forEach(function (tr, i) {
        var on = i >= (state.page - 1) * PER && i < state.page * PER;
        tr.classList.toggle('pg-hidden', !on);
      });
      rowsAll().forEach(function (tr) {
        if (tr.getAttribute('data-match') === '0') tr.classList.remove('pg-hidden');
      });
      var html = '<div class="page-btn' + (state.page === 1 ? ' disabled' : '') + '" data-p="' + (state.page - 1) + '">‹</div>';
      for (var p = 1; p <= pages; p++) {
        html += '<div class="page-btn' + (p === state.page ? ' active' : '') + '" data-p="' + p + '">' + p + '</div>';
      }
      html += '<div class="page-btn' + (state.page === pages ? ' disabled' : '') + '" data-p="' + (state.page + 1) + '">›</div>';
      pag.innerHTML = html;
    }

    pag.addEventListener('click', function (e) {
      var b = e.target.closest('.page-btn');
      if (!b || b.classList.contains('disabled')) return;
      state.page = Number(b.getAttribute('data-p'));
      render();
    });

    window.listPaginate = function (reset) {
      if (reset) state.page = 1;
      render();
    };

    render();
  }

  document.addEventListener('DOMContentLoaded', init);
})();
