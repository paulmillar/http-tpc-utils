<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:date="http://exslt.org/dates-and-times"
                extension-element-prefixes="date">

  <xsl:param name="fqdn"/>

  <xsl:output method="text"/>

  <xsl:template match="/results/DOWNTIME[SERVICE_TYPE='webdav' and SEVERITY='OUTAGE']">
    <xsl:if test="HOSTNAME=$fqdn">
      <xsl:choose>
	<xsl:when test="string-length(DESCRIPTION) > 50">
	  <xsl:value-of select="concat(substring(DESCRIPTION,1,50), '...')"/>
	</xsl:when>
	<xsl:otherwise>
	  <xsl:value-of select="DESCRIPTION"/>
	</xsl:otherwise>
      </xsl:choose>
    </xsl:if>
  </xsl:template>

  <xsl:template match="text()"/>
</xsl:stylesheet>
