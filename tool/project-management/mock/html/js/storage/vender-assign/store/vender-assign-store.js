(function () {
  var KEY = 'venderAssignList';

  var SEED = [
    {
      classId: 'CLS-001', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-001', teacherName: '田中 誠', state: 'done' }],
      subs: [{ vendor: 'TCV-002', teacherName: '鈴木 花子', state: 'done' }],
      attendeeVendor: 'TCV-004', attendee: '渡辺 直樹',
      motivationVendor: 'MC-01', motivationName: '小林 由美'
    },
    {
      classId: 'CLS-002', mainCount: 1, subCount: 0,
      mains: [{ vendor: 'TCV-003', teacherName: '', state: 'before' }],
      subs: [],
      attendeeVendor: '', attendee: '',
      motivationVendor: 'MC-02', motivationName: ''
    },
    {
      classId: 'CLS-004', mainCount: 2, subCount: 0,
      mains: [{ vendor: 'TCV-001', teacherName: '伊藤 美咲', state: 'done' }, { vendor: 'TCV-002', teacherName: '木村 隆', state: 'done' }],
      subs: [],
      attendeeVendor: 'TCV-005', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-005', mainCount: 1, subCount: 2,
      mains: [{ vendor: 'TCV-003', teacherName: '伊藤 美咲', state: 'done' }],
      subs: [{ vendor: 'TCV-004', teacherName: '渡辺 直樹', state: 'done' }, { vendor: 'TCV-005', teacherName: '中島 拓海', state: 'done' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-007', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-005', teacherName: '中島 拓海', state: 'done' }],
      subs: [{ vendor: 'TCV-004', teacherName: '小林 由美', state: 'done' }],
      attendeeVendor: 'TCV-003', attendee: '',
      motivationVendor: 'MC-01', motivationName: '田中 誠'
    },
    {
      classId: 'CLS-008', mainCount: 1, subCount: 0,
      mains: [],
      subs: [],
      requests: [{ vendor: 'TCV-003', main: 1, sub: 0 }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-009', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-002', teacherName: '', state: 'before' }],
      subs: [{ vendor: 'TCV-001', teacherName: '', state: 'before' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: 'MC-02', motivationName: '鈴木 花子'
    }
  ];

  function save(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) {}
  }

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) {}
    var seed = JSON.parse(JSON.stringify(SEED));
    save(seed);
    return seed;
  }

  function blank(classId) {
    return {
      classId: classId, mainCount: 1, subCount: 0,
      mains: [], subs: [],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationName: ''
    };
  }

  function find(classId) {
    var found = load().filter(function (a) { return a.classId === classId; })[0];
    return found || blank(classId);
  }

  function upsert(record) {
    var list = load().filter(function (a) { return a.classId !== record.classId; });
    list.push(record);
    save(list);
  }

  function requestsOf(rec) {
    if (!rec) return [];
    if (rec.requests) return rec.requests;
    if (rec.requested) return [{ vendor: rec.requestVendor || '', main: rec.requestMain || 0, sub: rec.requestSub || 0 }];
    return [];
  }

  function totalRequest(rec) {
    var t = requestsOf(rec).reduce(function (acc, r) {
      acc.main += r.main || 0;
      acc.sub += r.sub || 0;
      return acc;
    }, { main: 0, sub: 0 });
    t.main += (rec.mains || []).filter(function (p) { return p.state === 'requesting'; }).length;
    t.sub += (rec.subs || []).filter(function (p) { return p.state === 'requesting'; }).length;
    return t;
  }

  var STATUS = {
    REQUESTED: { label: '依頼済', tag: 'green' },
    REQUESTING: { label: '依頼中', tag: 'blue' },
    BEFORE: { label: '依頼前', tag: 'orange' },
    NONE: { label: '依頼無', tag: 'violet' },
    OPEN: { label: '依頼枠', tag: 'gray' }
  };

  function tag(s, style) {
    return '<span class="tag ' + s.tag + '"' + (style ? ' style="' + style + '"' : '') + '>' + s.label + '</span>';
  }

  window.VenderAssignStore = { load: load, save: save, find: find, upsert: upsert, blank: blank, requestsOf: requestsOf, totalRequest: totalRequest, STATUS: STATUS, tag: tag };
})();
