(function () {
  var WEEK = ['日', '月', '火', '水', '木', '金', '土'];

  function pad2(n) { return n < 10 ? '0' + n : '' + n; }
  function esc(v) {
    return String(v == null ? '' : v).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function dateKey(d) {
    return d.getFullYear() + '/' + pad2(d.getMonth() + 1) + '/' + pad2(d.getDate());
  }

  function create(opts) {
    var root = opts.root;
    var onEventClick = opts.onEventClick || function () {};
    var isHoliday = opts.isHoliday || function () { return false; };
    var today = new Date();
    var month = new Date(today.getFullYear(), today.getMonth(), 1);
    var columns = [];
    var events = {};
    var lastSig = null;
    var resetScroll = false;

    function render() {
      var y = month.getFullYear();
      var m = month.getMonth();
      var days = new Date(y, m + 1, 0).getDate();
      var html = '<div class="cal-nav"><div class="nav-btn" data-nav="prev">前月</div><b>' + y + '/' + pad2(m + 1) + '</b><div class="nav-btn" data-nav="next">翌月</div></div>';
      html += '<div class="cal-body">';
      if (!columns.length) {
        html += '<div>この月の予定はありません</div>';
      } else {
        var rows = '';
        for (var d = 1; d <= days; d++) {
          var date = new Date(y, m, d);
          var key = dateKey(date);
          var dayEvents = events[key] || [];
          var cls = isHoliday(key) ? 'holiday' : (date.getDay() === 0 ? 'sun' : (date.getDay() === 6 ? 'sat' : ''));
          rows += '<tr><td class="sticky day-date ' + cls + '">' + date.getDate() + '（' + WEEK[date.getDay()] + '）</td>';
          columns.forEach(function (c) {
            rows += '<td>';
            dayEvents.forEach(function (ev) {
              if (ev.colId === c.id) {
                var body = ev.lineHtml ? ev.lineHtml.map(function (l) { return '<div class="cal-line">' + l + '</div>'; }).join('') : esc(ev.label);
                rows += '<div class="cal-event ' + (ev.lineHtml ? 'cal-plain' : esc(ev.color || '')) + '" data-row="' + esc(ev.rowId) + '" data-step="' + esc(ev.stepId) + '"' + (ev.tip ? ' data-tip="' + esc(ev.tip) + '"' : '') + '>' + body + (ev.memo ? '<span class="memo-mark">!</span>' : '') + '</div>';
              }
            });
            rows += '</td>';
          });
          rows += '</tr>';
        }
        html += '<div class="scroll-outer"><table class="day-table"><thead><tr><th class="sticky">日付</th>';
        columns.forEach(function (c) {
          html += '<th data-tip="' + esc((c.tip || '')) + '">' + (c.label || []).map(esc).join('<br>') + '</th>';
        });
        html += '</tr></thead><tbody>' + rows + '</tbody></table></div>';
      }
      html += '</div>';
      var old = root.querySelector('.cal-body');
      var top = old ? old.scrollTop : 0;
      var left = old ? old.scrollLeft : 0;
      var pending = window.ScrollKeep ? ScrollKeep.take('.cal-body#0') : null;
      if (pending) {
        top = pending.top;
        left = pending.left;
      }
      if (resetScroll) {
        top = 0;
        left = 0;
        resetScroll = false;
      }
      root.innerHTML = html;
      var fresh = root.querySelector('.cal-body');
      if (fresh) {
        fresh.scrollTop = top;
        fresh.scrollLeft = left;
      }
    }

    root.addEventListener('click', function (e) {
      var nav = e.target.closest('[data-nav]');
      if (nav) {
        month = new Date(month.getFullYear(), month.getMonth() + (nav.getAttribute('data-nav') === 'next' ? 1 : -1), 1);
        resetScroll = true;
        render();
        return;
      }
      var ev = e.target.closest('.cal-event');
      if (ev) onEventClick(ev.getAttribute('data-row'), Number(ev.getAttribute('data-step')));
    });

    return {
      update: function (data) {
        columns = data.columns || [];
        events = data.events || {};
        var sig = columns.map(function (c) { return c.id; }).join('|');
        if (sig !== lastSig) {
          lastSig = sig;
          var keys = Object.keys(events).sort();
          var now = new Date();
          if (keys.length) {
            var p = keys[0].split('/');
            month = new Date(Number(p[0]), Number(p[1]) - 1, 1);
          } else {
            month = new Date(now.getFullYear(), now.getMonth(), 1);
          }
        }
        render();
      },
      render: render
    };
  }

  function bindView(o) {
    var tabs = Array.prototype.slice.call(o.tabs.querySelectorAll('.seg-opt'));
    var active = false;
    function show(cal) {
      active = cal;
      o.table.style.display = cal ? 'none' : '';
      o.calendar.style.display = cal ? '' : 'none';
      if (cal) o.render();
    }
    tabs.forEach(function (tab) {
      tab.addEventListener('click', function () {
        tabs.forEach(function (x) { x.classList.remove('is-active'); });
        tab.classList.add('is-active');
        var cal = tab.getAttribute('data-view') === 'calendar';
        try { localStorage.setItem(o.storageKey, cal ? 'calendar' : 'table'); } catch (e) {}
        show(cal);
      });
    });
    document.addEventListener('click', function () { if (active) setTimeout(o.render, 0); }, true);
    document.addEventListener('input', function () { if (active) o.render(); });
    var saved = null;
    try { saved = localStorage.getItem(o.storageKey); } catch (e) {}
    if (saved === 'calendar') {
      tabs.forEach(function (x) { x.classList.toggle('is-active', x.getAttribute('data-view') === 'calendar'); });
      show(true);
    }
    return { isActive: function () { return active; } };
  }

  window.DayTable = { create: create, bindView: bindView };
})();
