(function () {
  var ROLES = ['main', 'sub', 'special'];
  var HEAD = { font: { bold: true, color: { rgb: 'FFFFFF' } }, fill: { patternType: 'solid', fgColor: { rgb: '1C2B45' } }, alignment: { horizontal: 'center', vertical: 'center', wrapText: true }, border: { top: { style: 'thin', color: { rgb: '8A94A6' } }, bottom: { style: 'thin', color: { rgb: '8A94A6' } }, left: { style: 'thin', color: { rgb: '8A94A6' } }, right: { style: 'thin', color: { rgb: '8A94A6' } } } };
  var GRAY = { fill: { patternType: 'solid', fgColor: { rgb: 'D9D9D9' } } };

  function build(snap) {
    var maxOf = snap.maxOf;
    var header = snap.header;
    var aoa = [['講師ベンダー', snap.vendor], [], header].concat(snap.rows.map(function (r) { return r.line; }));
    var ws = XLSX.utils.aoa_to_sheet(aoa);

    snap.rows.forEach(function (r, ri) {
      var col = snap.teacherStart;
      ROLES.forEach(function (role) {
        for (var k = 0; k < maxOf[role]; k++) {
          if (k >= r.counts[role]) {
            var addr = XLSX.utils.encode_cell({ r: ri + 3, c: col });
            if (!ws[addr]) ws[addr] = { t: 's', v: '' };
            ws[addr].s = GRAY;
          }
          col++;
        }
      });
    });

    var specialStart = snap.teacherStart + maxOf.main + maxOf.sub;
    snap.rows.forEach(function (r, ri) {
      if (!r.memo || !maxOf.special) return;
      var addr = XLSX.utils.encode_cell({ r: ri + 3, c: specialStart });
      if (!ws[addr]) ws[addr] = { t: 's', v: '' };
      ws[addr].c = [{ a: '備考', t: r.memo }];
    });

    header.forEach(function (_, ci) {
      var addr = XLSX.utils.encode_cell({ r: 2, c: ci });
      if (!ws[addr]) ws[addr] = { t: 's', v: '' };
      ws[addr].s = HEAD;
    });
    ws['A1'].s = HEAD;
    ws['B1'].s = { border: HEAD.border, alignment: { vertical: 'center' } };
    ws['!cols'] = header.map(function (name, ci) {
      if (ci === 1) return { wch: 32 };
      if (ci === 6) return { wch: 8 };
      if (ci < 6) return { wch: 14 };
      return { wch: 28 };
    });
    ws['!rows'] = [{ hpt: 18 }, {}, { hpt: 18 }];
    Object.keys(ws).forEach(function (k) {
      if (k.charAt(0) === '!') return;
      var cell = ws[k];
      var st = cell.s || {};
      cell.s = Object.assign({}, st, { alignment: Object.assign({}, st.alignment || {}, { vertical: 'center' }) });
    });
    return ws;
  }

  window.VenderSheet = {
    save: function (snap) {
      var wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, build(snap), '登壇依頼');
      XLSX.writeFile(wb, '登壇依頼-' + snap.vendor + '.xlsx');
    }
  };
})();
