FROM quay.io/centos/centos:stream9 as build

######[ Variables to update ]##############
# Update for new versions of modsecurity / owasp
ENV MODSECURITY_VERSION=3.0.10

# 23-jul-2023
ENV OWASP_VERSION=3.3.5 

########[ Nothing to edit below this point ]############

# package install done in Dockerfile, to use Docker layer cache
RUN dnf install -y 'dnf-command(config-manager)'
RUN dnf config-manager --set-enabled crb
RUN dnf install -y git make gcc cmake autoconf automake libtool g++ pcre2-devel libcurl-devel libxml2-devel diffutils libevent-devel lua lua-devel

# We need lua-static and pcre2-static. cannot find in which repository it is stored ...
# TODO: compile spoa in static mode. Not working, so these packages are not needed right now
# RUN rpm -i https://kojihub.stream.centos.org/kojifiles/packages/lua/5.4.4/4.el9/x86_64/lua-static-5.4.4-4.el9.x86_64.rpm
# RUN rpm -i https://kojihub.stream.centos.org/kojifiles/packages/pcre2/10.40/2.el9/x86_64/pcre2-static-10.40-2.el9.x86_64.rpm

ENV CFLAGS="-O3 -fPIE -fstack-protector-all -D_FORTIFY_SOURCE=2 -fno-strict-aliasing -fPIC"
ENV CXXFLAGS=${CFLAGS}
ENV LDFLAGS="-Wl,-z,now -Wl,-z,relro"
ENV PREFIX=/build
ENV SOURCES="/sources"

# Sources of inspiration:
# https://github.com/haproxy/spoa-modsecurity/issues/8#issuecomment-1595216018
# https://github.com/rikatz/spoa-modsecurity-python/blob/main/build-modsecurity.sh


RUN mkdir $SOURCES && cd $SOURCES

RUN echo "Installing yajl" \
    && cd $SOURCES \
    && git clone https://github.com/lloyd/yajl \
    && cd $SOURCES/yajl && ./configure --prefix ${PREFIX} && make install

RUN echo "Installing ssdeep" \
    && cd $SOURCES \
    && git clone https://github.com/ssdeep-project/ssdeep \
    && cd $SOURCES/ssdeep \
    && ./bootstrap \
    && ./configure --prefix=${PREFIX} \
    && make install

RUN echo "Installing lmdb" \
    && cd $SOURCES \
    && git clone https://github.com/LMDB/lmdb \
    && cd $SOURCES/lmdb/libraries/liblmdb \
    && sed -i "s#/usr/local#${PREFIX}#g" Makefile \
    && sed -i "s#-O2 -g#${CFLAGS}#g" Makefile \
    && make install

RUN echo "Installing libmaxmind" \
    && cd $SOURCES \
    && git clone --recurse-submodules https://github.com/maxmind/libmaxminddb \
    && cd $SOURCES/libmaxminddb \
    && ./bootstrap \
    && ./configure --disable-tests --disable-shared --prefix=${PREFIX} \
    && make \
    && make install

RUN echo "Installing ModSecurity" \
    && cd $SOURCES \
    && git clone --recurse-submodules https://github.com/SpiderLabs/ModSecurity -b v${MODSECURITY_VERSION} \
    && cd $SOURCES/ModSecurity \
    && ./build.sh \
    && sed -i "s#/usr/lib /usr/local/lib /usr/local/fuzzy /usr/local/libfuzzy /usr/local /opt /usr /usr/lib64 /opt/local#${PREFIX}#g" configure \
    && sed -i 's#LUA_POSSIBLE_EXTENSIONS=".*#LUA_POSSIBLE_EXTENSIONS="so"#g' configure \
    && sed -i 's#LUA_POSSIBLE_PATHS=".*"#LUA_POSSIBLE_PATHS="/usr/lib64"#g' configure \
    && ./configure --with-pcre2=yes --with-lmdb=${PREFIX} --with-lua=yes --with-maxmind=${PREFIX} --with-ssdeep=${PREFIX} --with-yajl=${PREFIX} --prefix=${PREFIX} \
    && make -j4 \
    && make install

RUN echo "Installing spoa-modsecurity" \
    && cd $SOURCES \
    && git clone https://github.com/FireBurn/spoa-modsecurity \
    && cd $SOURCES/spoa-modsecurity \
    && sed -i "s#ModSecurity-v3.0.5/INSTALL/usr/local/modsecurity#${PREFIX}#g" Makefile \
    && sed -i "s#-Wall -Werror -pthread -O2 -g -fsanitize=address -fno-omit-frame-pointer#${CFLAGS}#g" Makefile \
    && sed -i "s#-lasan##g" Makefile \
    # && sed -i 's#$(MODSEC_LIB)/libmodsecurity.so#-Wl,-Bstatic $(MODSEC_LIB)/libmodsecurity.a $(MODSEC_LIB)/libyajl_s.a $(MODSEC_LIB)/liblmdb.a $(MODSEC_LIB)/libmaxminddb.a $(MODSEC_LIB)/libfuzzy.a /usr/lib64/liblua.a -Wl,-Bdynamic#g' Makefile \
    && make \
    && strip modsecurity \
    && cp -a modsecurity /usr/bin/modsecurity

RUN echo "Installing owasp rules" \
    && cd $SOURCES \
    && curl -s -L -o owasp.tgz https://github.com/coreruleset/coreruleset/archive/refs/tags/v${OWASP_VERSION}.tar.gz \
    && tar -xf owasp.tgz \
    && mv coreruleset-${OWASP_VERSION} $PREFIX/coreruleset \
    && /bin/rm -rf $PREFIX/coreruleset/{.github,tests,docs} $PREFIX/coreruleset/*.md $PREFIX/coreruleset/{INSTALL,KNOWN_BUGS,.git*,.*.yml}

############################################################################
# Runtime image, containing only modsecurity binary (compiled as static)
FROM quay.io/centos/centos:stream9 as runtime

COPY --from=build /usr/bin/modsecurity /usr/bin/modsecurity
COPY --from=build /build/lib/*.so* /usr/lib64

# Copy owasp
RUN mkdir /rules
COPY --from=build /build/coreruleset /rules/coreruleset

CMD [ "/usr/bin/modsecurity", "-f", "/rules/modsecurity.conf"]
