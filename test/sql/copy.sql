LOAD 'chdb';

CREATE TABLE logs (
    req_id    BIGINT PRIMARY KEY,
    name      TEXT     NOT NULL,
    path      TEXT     NOT NULL
);

INSERT INTO logs
VALUES (1, 'page_view',   '/users/profile')
     , (2, 'Page_View',   '/users/settings')
     , (3, 'PAGE_VIEW',   '/admin/dashboard')
     , (4, 'add_to_cart', '/products/shoes')
    --    (5, 'Add_To_Cart', '/products/hats'),
    --    (6, 'purchase',    '/checkout'),
    --    (7, 'PURCHASE',    '/checkout/confirm'),
    --    (8, 'share',       '/social/twitter'),
    --    (9, 'logout',      '/auth/logout'),
    --    (10, 'signup',     '/auth/signup')
;

-- COPY without URL should just work.
COPY logs TO STDOUT;

-- Should intercept known URLs schemas.
COPY logs TO 's3://lol';
COPY logs TO 'http://lol';
COPY logs TO 'https://lol';
COPY logs TO 'gcs://lol';
COPY logs TO 'abs://lol';

COPY logs FROM 's3://lol';
COPY logs FROM 'http://lol';
COPY logs FROM 'https://lol';
COPY logs FROM 'gcs://lol';
COPY logs FROM 'abs://lol';

COPY logs FROM 's3://lol.parquet' (
    access_key 'key',
    access_secret 'secret',
    session_token 'big fat token',
    format 'parquet',
    structure 'id Int64',
    compression 'lz4'
);

COPY logs TO 'gcs://lol.parquet' (
    ACCESS_KEY 'gcs_key',
    ACCESS_SECRET 'gcs_secret',
    STRUCTURE 'id UInt64',
    compression 'snappy'
);

COPY logs TO 'gcs://lol.parquet' (
    ACCESS_KEY 'gcs_key',
    ACCESS_SECRET 'gcs_secret',
    STRUCTURE 'id UInt64'
);

COPY logs FROM 'https://example.com/data.csv' (
    FORMAT 'TSVWithNamesAndTypes',
    STRUCTURE 'id UInt32'
);

COPY logs FROM 'https://example.com/data.csv' (
    STRUCTURE 'id UInt32'
);
