/* IMPORTANT
 * This snapshot file is auto-generated, but designed for humans.
 * It should be checked into source control and tracked carefully.
 * Re-generate by setting TAP_SNAPSHOT=1 and running tests.
 * Make sure to inspect the output below.  Do not ignore changes!
 */
'use strict'
exports[`t/grammar.js > TAP > 001 - 2 flags 1`] = `
Array [
  "13954",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/etc/ld.so.cache\\"",
      "O_RDONLY",
      Array [
        Array [
          "|",
          "O_CLOEXEC",
        ],
      ],
      undefined,
      Object {
        "complete": Object {
          "ret": "3",
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 002 - 3 flags 1`] = `
Array [
  "14802",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/proc/self/mountinfo\\"",
      "O_RDONLY",
      Array [
        Array [
          "|",
          "O_LARGEFILE",
        ],
        Array [
          "|",
          "O_CLOEXEC",
        ],
      ],
      undefined,
      Object {
        "complete": Object {
          "ret": "3",
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 003 - ENOENT 1`] = `
Array [
  "13954",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/usr/lib/tls/libtinfo.so.6\\"",
      "O_RDONLY",
      Array [
        Array [
          "|",
          "O_CLOEXEC",
        ],
      ],
      undefined,
      Object {
        "complete": Object {
          "err": Array [
            "-1",
            "ENOENT",
            "(No such file or directory)",
          ],
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 004 - exit 1`] = `
Array [
  "13955",
  Object {
    "exit": null,
  },
]
`

exports[`t/grammar.js > TAP > 005 - 1 flag 1`] = `
Array [
  "13954",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/usr/lib/gconv/gconv-modules.cache\\"",
      "O_RDONLY",
      undefined,
      undefined,
      Object {
        "complete": Object {
          "err": Array [
            "-1",
            "ENOENT",
            "(No such file or directory)",
          ],
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 006 - mode 1`] = `
Array [
  "13954",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/dev/null\\"",
      "O_WRONLY",
      Array [
        Array [
          "|",
          "O_CREAT",
        ],
        Array [
          "|",
          "O_TRUNC",
        ],
        Array [
          "|",
          "O_LARGEFILE",
        ],
      ],
      ", 0666",
      Object {
        "complete": Object {
          "ret": "3",
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 007 - 000 mode 1`] = `
Array [
  "13966",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/home/andy/dev/nano-pacstrap32/newroot/var/lib/pacman/db.lck\\"",
      "O_WRONLY",
      Array [
        Array [
          "|",
          "O_CREAT",
        ],
        Array [
          "|",
          "O_EXCL",
        ],
        Array [
          "|",
          "O_LARGEFILE",
        ],
        Array [
          "|",
          "O_CLOEXEC",
        ],
      ],
      ", 000",
      Object {
        "complete": Object {
          "ret": "4",
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 008 - unfinished 1`] = `
Array [
  "14005",
  Object {
    "openat": Array [
      "AT_FDCWD",
      "\\"/proc/self/fd\\"",
      "O_RDONLY",
      Array [
        Array [
          "|",
          "O_LARGEFILE",
        ],
        Array [
          "|",
          "O_DIRECTORY",
        ],
      ],
      undefined,
      Object {
        "unfinished": null,
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 009 - resumed 1`] = `
Array [
  "14005",
  Object {
    "resumed": Array [
      "openat",
      Object {
        "ret": "11",
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 010 - execve 1`] = `
Array [
  "13954",
  Object {
    "execve": Array [
      "\\"/usr/bin/setarch\\"",
      Object {
        "complete": Object {
          "ret": "0",
        },
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 011 - execve unfinished 1`] = `
Array [
  "13977",
  Object {
    "execve": Array [
      "\\"/usr/bin/gpgsm\\"",
      Object {
        "unfinished": null,
      },
    ],
  },
]
`

exports[`t/grammar.js > TAP > 012 - signal 1`] = `
Array [
  "13966",
  Object {
    "signal": null,
  },
]
`
