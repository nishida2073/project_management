(function () {
  var KEY = 'venderAssignList';

  var SEED = [
    {
      classId: 'CLS-001', contractMain: 'HKG000016801', contractSub: 'HKG000017801', docNo: '0001500001', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-001', teacherName: '田中 誠', state: 'done' }],
      subs: [{ vendor: 'TCV-002', teacherName: '鈴木 花子', state: 'done' }],
      attendeeVendor: '株式会社ABCラーニング', attendee: '渡辺 直樹',
      motivationVendor: 'MC-01', motivationName: '小林 由美'
    },
    {
      classId: 'CLS-002', contractMain: 'HKG000016802', contractSub: '', docNo: '0001500002', mainCount: 1, subCount: 0,
      mains: [{ vendor: 'TCV-003', teacherName: '', state: 'before' }],
      subs: [],
      attendeeVendor: '', attendee: '',
      motivationVendor: 'MC-02', motivationName: ''
    },
    {
      classId: 'CLS-004', contractMain: 'HKG000016804', contractSub: '', docNo: '0001500004', mainCount: 2, subCount: 0,
      mains: [{ vendor: 'TCV-001', teacherName: '伊藤 美咲', state: 'done' }, { vendor: 'TCV-002', teacherName: '木村 隆', state: 'done' }],
      subs: [],
      attendeeVendor: '株式会社XYZスキル', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-005', contractMain: 'HKG000016805', contractSub: 'HKG000017805', docNo: '0001500005', mainCount: 1, subCount: 2,
      mains: [{ vendor: 'TCV-003', teacherName: '伊藤 美咲', state: 'done' }],
      subs: [{ vendor: 'TCV-004', teacherName: '渡辺 直樹', state: 'done' }, { vendor: 'TCV-005', teacherName: '中島 拓海', state: 'done' }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-007', contractMain: 'HKG000016807', contractSub: 'HKG000017807', docNo: '0001500007', mainCount: 1, subCount: 1,
      mains: [{ vendor: 'TCV-005', teacherName: '中島 拓海', state: 'done' }],
      subs: [{ vendor: 'TCV-004', teacherName: '小林 由美', state: 'done' }],
      attendeeVendor: '株式会社サンプル教育', attendee: '',
      motivationVendor: 'MC-01', motivationName: '田中 誠'
    },
    {
      classId: 'CLS-008', contractMain: 'HKG000016808', contractSub: '', docNo: '0001500008', mainCount: 1, subCount: 0,
      mains: [],
      subs: [],
      requests: [{ vendor: 'TCV-003', main: 1, sub: 0 }],
      attendeeVendor: '', attendee: '',
      motivationVendor: '', motivationName: ''
    },
    {
      classId: 'CLS-009', contractMain: 'HKG000016809', contractSub: 'HKG000017809', docNo: '0001500009', mainCount: 1, subCount: 1,
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
      mains: [], subs: [], specials: [],
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
      acc.special += r.special || 0;
      return acc;
    }, { main: 0, sub: 0, special: 0 });
    t.main += (rec.mains || []).filter(function (p) { return p.state === 'requesting'; }).length;
    t.sub += (rec.subs || []).filter(function (p) { return p.state === 'requesting'; }).length;
    t.special += (rec.specials || []).filter(function (p) { return p.state === 'requesting'; }).length;
    return t;
  }

  var STATUS = SlotStatusStore.STATUS;
  var tag = SlotStatusStore.tag;

  window.VenderAssignStore = { load: load, save: save, find: find, upsert: upsert, blank: blank, requestsOf: requestsOf, totalRequest: totalRequest, STATUS: STATUS, tag: tag };
})();
