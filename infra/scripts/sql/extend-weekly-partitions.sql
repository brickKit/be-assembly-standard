-- 过渡（06b 设计轮 data-layer §6 第 0 步）：测试库里组件不运行，没人续建周分区。test-db-init 每次给周分区
-- 快用完的表补到今天 +56 天；SDK 接管分区创建（设计轮议题"分区窗口"）后删掉本文件与调用。
DO $$
DECLARE p record; last_d date; prev_d date; d date; owner text; created int := 0;
BEGIN
  FOR p IN
    SELECT n.nspname s, c.relname t, c.oid
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind='p' AND n.nspname !~ '_archive$'
  LOOP
    SELECT max(to_date(right(k.relname,10),'YYYY_MM_DD')) INTO last_d
      FROM pg_inherits i JOIN pg_class k ON k.oid=i.inhrelid
      WHERE i.inhparent=p.oid AND k.relname ~ ('^'||p.t||'_\d{4}_\d{2}_\d{2}$');
    CONTINUE WHEN last_d IS NULL;
    SELECT max(to_date(right(k.relname,10),'YYYY_MM_DD')) INTO prev_d
      FROM pg_inherits i JOIN pg_class k ON k.oid=i.inhrelid
      WHERE i.inhparent=p.oid AND k.relname ~ ('^'||p.t||'_\d{4}_\d{2}_\d{2}$')
        AND to_date(right(k.relname,10),'YYYY_MM_DD') < last_d;
    CONTINUE WHEN prev_d IS NULL OR last_d - prev_d <> 7;
    owner := pg_get_userbyid((SELECT relowner FROM pg_class WHERE oid=p.oid));
    d := last_d + 7;
    WHILE d < current_date + 56 LOOP
      EXECUTE format('SET LOCAL ROLE %I', owner);
      EXECUTE format('CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
        p.s, p.t||'_'||to_char(d,'YYYY_MM_DD'), p.s, p.t, d, d+7);
      EXECUTE 'RESET ROLE';
      created := created + 1;
      d := d + 7;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'created % partitions', created;
END $$;
