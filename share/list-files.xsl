<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:date="http://exslt.org/dates-and-times"
                extension-element-prefixes="date">

  <xsl:param name="path"/>

  <xsl:output method="text"/>

  <xsl:template match="d:response[d:propstat/d:prop/d:resourcetype[not(d:collection)]]" xmlns:d="DAV:">
    <xsl:value-of select="concat(substring-after(d:href,concat($path,'/')),'&#x0a;')"/>
  </xsl:template>

  <xsl:template match="text()"/>
</xsl:stylesheet>
