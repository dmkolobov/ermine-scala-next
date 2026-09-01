# Controls for `core/examples/shouldfail/`

Every file in this directory MUST LOAD.

They exist so that the should-fail cases next door cannot be dismissed as
"that helper's signature was unsatisfiable all along". Each control uses the
same row-polymorphic signature as its should-fail partner, instantiated at
arguments that DO satisfy it. If a control stops loading, the corresponding
should-fail case is no longer evidence of anything.

    ERMINE_JAVA_OPTS=-Dermine.useInterface=false bin/ermine \
      core/examples/shouldfail-controls/*.e </dev/null
